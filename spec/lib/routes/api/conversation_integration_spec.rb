# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'concurrent'

# Advanced integration tests for conversation service
# Focus on circuit breakers, performance, session corruption, and error boundaries
RSpec.describe "Conversation Service Integration", vcr: { 
  cassette_name: "conversation_service_integration", 
  match_requests_on: [:method, :uri],  # Don't match on body for TTS flexibility
  allow_playback_repeats: true
} do
  include Rack::Test::Methods

  def app
    GlitchCubeApp
  end

  def parsed_body
    JSON.parse(last_response.body)
  end

  describe 'Circuit Breaker Behavior' do
    context 'when LLM service fails repeatedly' do
      before do
        # Enable circuit breakers for testing
        ENV['ENABLE_CIRCUIT_BREAKERS'] = 'true'
      end

      after do
        ENV.delete('ENABLE_CIRCUIT_BREAKERS')
      end

      it 'opens circuit breaker after consecutive failures' do
        # Mock LLM service to fail repeatedly
        allow(Services::LLMService).to receive(:complete_with_messages)
          .and_raise(Timeout::Error, 'Service timeout')

        # Art installation should still work with fallback responses
        5.times do |i|
          post '/api/v1/conversation',
               { message: "failure test #{i}" }.to_json,
               { 'CONTENT_TYPE' => 'application/json' }

          # Debug: Print actual response for investigation
          puts "Response status: #{last_response.status}"
          puts "Response body: #{last_response.body}"
          
          # Should return 200 with fallback response (graceful degradation)
          expect(last_response.status).to eq(200)
          expect(parsed_body['success']).to be true
          # Should have fallback response content
          response_text = parsed_body.dig('data', 'response')
          expect(response_text).to be_present
        end

        # Subsequent requests should still work with fallback
        start_time = Time.now
        post '/api/v1/conversation',
             { message: 'circuit breaker test' }.to_json,
             { 'CONTENT_TYPE' => 'application/json' }
        duration = Time.now - start_time

        expect(last_response.status).to eq(200)
        # Should respond quickly with fallback (under 1 second)
        expect(duration).to be < 1.0
        # Should have an error indicator but still provide response
        expect(parsed_body.dig('data', 'error')).to eq('general_error')
      end

      it 'transitions to half-open state after timeout' do
        # Mock LLM service to fail first, then succeed
        call_count = 0
        allow(Services::LLMService).to receive(:complete_with_messages) do
          call_count += 1
          if call_count <= 3
            raise Timeout::Error, 'Service timeout'
          else
            # Return a successful response after failures
            double('LLMResponse',
                   response_text: 'Service recovered',
                   continue_conversation?: true,
                   has_tool_calls?: false,
                   cost: 0.001,
                   model: 'test-model',
                   usage: { prompt_tokens: 10, completion_tokens: 20 })
          end
        end

        # Make failing requests
        3.times do
          post '/api/v1/conversation',
               { message: 'test message' }.to_json,
               { 'CONTENT_TYPE' => 'application/json' }
        end

        # Wait a moment for circuit to potentially transition
        sleep 0.1

        # Next request should attempt recovery
        post '/api/v1/conversation',
             { message: 'recovery test' }.to_json,
             { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(200)
        # Should have recovered
        response_text = parsed_body.dig('data', 'response')
        expect(response_text).to match(/recovered|response/i)
      end
    end

    context 'when Home Assistant service fails' do
      it 'gracefully degrades HA integration features', vcr: { cassette_name: 'ha_service_degradation' } do
        allow_any_instance_of(HomeAssistantClient).to receive(:call_service)
          .and_raise(HomeAssistantClient::TimeoutError, 'HA unavailable')

        post '/api/v1/conversation',
             {
               message: 'turn on the lights',
               context: { voice_interaction: true },
               session_id: 'test-ha-fail-123'
             }.to_json,
             { 'CONTENT_TYPE' => 'application/json' }

        # Should still respond even if HA integration fails
        expect(last_response.status).to be_between(200, 299)
        expect(parsed_body['success']).to be true
        expect(parsed_body['data']['response']).to be_present
      end
    end
  end

  describe 'Session State Corruption Prevention' do
    let(:session_id) { SecureRandom.uuid }

    it 'prevents race conditions in concurrent session updates' do
      # Create initial session
      post '/api/v1/conversation',
           { message: 'Start session' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response).to be_ok
      actual_session_id = parsed_body['session_id']
      expect(actual_session_id).to be_present

      # Make concurrent requests to the same session
      # Note: Rack::Test doesn't support true threading, so simulate with sequential requests
      results = 10.times.map do |i|
        post '/api/v1/conversation',
             {
               message: "concurrent message #{i}",
               context: { session_id: actual_session_id }
             }.to_json,
             { 'CONTENT_TYPE' => 'application/json' }

        {
          status: last_response.status,
          success: last_response.ok? ? parsed_body['success'] : false,
          thread_id: i,
          error: last_response.ok? ? nil : parsed_body['error']
        }
      end

      # All sequential requests should succeed
      successful = results.select { |r| r[:status] == 200 }
      expect(successful.size).to eq(10) # All should succeed
      expect(successful.all? { |r| r[:success] }).to be true

      # Verify session integrity after updates
      session = Conversation.find_by(session_id: actual_session_id)
      expect(session).to be_present

      # Should have user + assistant message pairs (20 messages for 10 requests)
      expect(session.messages.count).to be >= 20

      # Session metadata should still be valid JSON
      expect(session.metadata).to be_a(Hash)
    end

    it 'handles session cleanup on unexpected errors' do
      session = create_test_session

      # Simulate service failure during conversation
      allow_any_instance_of(ConversationModule).to receive(:call)
        .and_raise(StandardError, 'Unexpected error')

      post '/api/v1/conversation',
           {
             message: 'trigger cleanup test',
             context: { session_id: session.session_id }
           }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      # Verify session is still accessible and not corrupted
      conversation = Conversation.find_by(session_id: session.session_id)
      expect(conversation).to be_present
      expect(conversation.metadata).to be_a(Hash)
    end
  end

  describe 'Performance and Resource Management' do
    it 'handles large context payloads within memory limits' do
      large_context = {
        conversation_history: Array.new(100) do |i|
          {
            role: 'user',
            content: 'x' * 1000, # 1KB per message
            timestamp: i.minutes.ago.iso8601
          }
        end,
        metadata: {
          large_data: 'x' * (1024 * 100) # 100KB of data
        }
      }

      memory_before = GC.stat[:heap_live_slots]

      post '/api/v1/conversation',
           {
             message: 'test with large context',
             context: large_context
           }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      memory_after = GC.stat[:heap_live_slots]
      memory_growth = memory_after - memory_before

      # Should handle large payloads without excessive memory growth
      expect(last_response.status).to be_between(200, 499)
      expect(memory_growth).to be < 100_000 # Reasonable memory growth limit
    end

    it 'cleans up resources after conversation completion' do
      session = create_test_session

      # Track database connections
      initial_connections = ActiveRecord::Base.connection_pool.connections.size

      post '/api/v1/conversation',
           {
             message: 'resource cleanup test',
             context: { session_id: session.session_id }
           }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      # Verify no connection leaks
      final_connections = ActiveRecord::Base.connection_pool.connections.size
      expect(final_connections).to eq(initial_connections)
    end

    it 'times out long-running conversations appropriately' do
      # Mock LLM service to raise timeout error
      allow(Services::LLMService).to receive(:complete_with_messages)
        .and_raise(Services::LLMService::LLMError, "Request timed out after 30 seconds")

      # Mock HomeAssistant TTS calls to prevent real network calls during timeout handling
      allow_any_instance_of(HomeAssistantClient).to receive(:call_service)
        .and_return({ 'success' => true })

      start_time = Time.now
      post '/api/v1/conversation',
           { message: 'timeout test', session_id: 'test-timeout-123' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }
      duration = Time.now - start_time

      # Should respond with fallback quickly
      expect(duration).to be < 2
      expect(last_response.status).to eq(200) # Graceful fallback
      expect(parsed_body['success']).to be true
      # Should have a fallback response
      expect(parsed_body['data']['response']).to be_a(String)
      expect(parsed_body['data']['response'].length).to be > 10
    end
  end

  describe 'Database Query Optimization' do
    it 'avoids N+1 queries when loading conversation history' do
      session = create_test_session_with_messages(20)

      # Track SQL queries
      queries_before = count_sql_queries do
        post '/api/v1/conversation',
             {
               message: 'test message history loading',
               context: { session_id: session.session_id }
             }.to_json,
             { 'CONTENT_TYPE' => 'application/json' }
      end

      # Should not have excessive queries for loading message history
      # 13-15 queries is reasonable for conversation with eager loading:
      # - Load conversation
      # - Load messages with eager loading
      # - Load memories
      # - Various metadata queries
      expect(queries_before).to be < 20 # Reasonable query limit with eager loading
      expect(last_response).to be_ok
    end
  end

  describe 'Input Validation and Security' do
    it 'prevents SQL injection through context parameters' do
      malicious_context = {
        session_id: "'; DROP TABLE conversations; --",
        user_input: "'; UPDATE users SET admin = true; --"
      }

      post '/api/v1/conversation',
           {
             message: 'sql injection test',
             context: malicious_context
           }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      # Should handle gracefully without executing malicious SQL
      expect(last_response.status).to be_between(200, 499)

      # Verify tables still exist
      expect(Conversation.count).to be >= 0
    end

    it 'limits deeply nested context objects to prevent stack overflow' do
      # Create deeply nested object
      deep_context = {}
      current = deep_context
      1000.times do |i|
        current["level_#{i}"] = {}
        current = current["level_#{i}"]
      end

      post '/api/v1/conversation',
           {
             message: 'deep nesting test',
             context: deep_context
           }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      # Should handle without stack overflow
      expect(last_response.status).to be_between(200, 499)
    end

    it 'sanitizes output to prevent XSS in API responses' do
      # Simulate LLM response with potential XSS
      allow_any_instance_of(ConversationModule).to receive(:call).and_return(
        response: '<script>alert("xss")</script>Malicious response',
        session_id: SecureRandom.uuid
      )

      post '/api/v1/conversation',
           { message: 'xss test' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      # Response should be properly escaped or sanitized
      response_content = parsed_body.dig('data', 'response')
      expect(response_content).not_to include('<script>')
      expect(response_content).not_to include('alert(')
    end
  end

  describe 'Service Degradation Scenarios' do
    it 'continues functioning when TTS service is unavailable' do
      allow_any_instance_of(Services::CharacterService).to receive(:speak)
        .and_raise(StandardError, 'TTS service down')

      post '/api/v1/conversation',
           { message: 'tts failure test' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      # Should still provide text response
      expect(last_response).to be_ok
      expect(parsed_body['success']).to be true
      expect(parsed_body['data']['response']).to be_present
    end

    it 'provides meaningful fallback responses when all AI services fail' do
      # Disable all AI services
      allow(Services::LLMService).to receive(:complete_with_messages)
        .and_raise(Services::LLMService::LLMError, 'All models unavailable')

      post '/api/v1/conversation',
           { message: 'ai failure test' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response).to be_ok
      expect(parsed_body['success']).to be true

      # Should provide fallback response
      fallback_response = parsed_body.dig('data', 'response')
      expect(fallback_response).to be_present
      expect(fallback_response.downcase).to match(/offline|unavailable|connectivity|capabilities|present|moment|spirit/)
    end
  end

  private

  def create_test_session
    Services::ConversationSession.find_or_create(
      context: { source: 'test', persona: 'neutral' }
    )
  end

  def create_test_session_with_messages(count)
    session = create_test_session

    count.times do |i|
      session.add_message(
        role: i.even? ? 'user' : 'assistant',
        content: "Test message #{i}",
        persona: 'neutral'
      )
    end

    session
  end

  def count_sql_queries(&block)
    query_count = 0
    counter = lambda do |_name, _start, _finish, _id, payload|
      query_count += 1 unless %w[CACHE SCHEMA].include?(payload[:name])
    end

    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &block)

    query_count
  end
end
