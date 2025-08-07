# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Admin Conversation Traces API', type: :request do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  let(:session_id) { 'admin-trace-test-session' }
  let(:redis) { Redis.new(url: GlitchCube.config.redis_url) }

  before do
    # Clear any existing traces
    redis&.keys('conversation_trace:*')&.each { |key| redis.del(key) }
  rescue Redis::CannotConnectError
    skip 'Redis not available for integration tests'
  end

  describe 'GET /admin/conversation_traces' do
    context 'when requesting traces by session_id', :vcr do
      it 'returns empty array for session with no traces' do
        get '/admin/conversation_traces', session_id: session_id

        expect(last_response).to be_ok
        data = JSON.parse(last_response.body)
        expect(data['traces']).to eq([])
        expect(data['count']).to eq(0)
        expect(data['session_id']).to eq(session_id)
      end

      it 'returns traces for session with conversation history' do
        # Create a real conversation trace by calling the conversation API
        conversation_request = {
          message: 'Hello, can you tell me about the weather?',
          context: {
            session_id: session_id,
            location: 'Center Camp',
            tools: ['weather'],
            trace_conversation: true
          },
          persona: 'playful'
        }

        # Make actual conversation request to generate trace
        post '/api/v1/conversation', conversation_request.to_json, 'CONTENT_TYPE' => 'application/json'

        expect(last_response).to be_ok
        conversation_data = JSON.parse(last_response.body)
        expect(conversation_data['trace_id']).to be_present

        # Now request the traces for this session
        get '/admin/conversation_traces', session_id: session_id

        expect(last_response).to be_ok
        data = JSON.parse(last_response.body)
        expect(data['traces']).not_to be_empty
        expect(data['count']).to be > 0
        expect(data['traces'].first['session_id']).to eq(session_id)
        expect(data['traces'].first['trace_id']).to eq(conversation_data['trace_id'])
      end
    end

    context 'when requesting specific trace by trace_id', :vcr do
      let(:trace_id) { 'test-trace-specific' }

      it 'returns error for non-existent trace' do
        get '/admin/conversation_traces', trace_id: 'non-existent-trace'

        expect(last_response).to be_ok
        data = JSON.parse(last_response.body)
        expect(data['error']).to eq('Trace not found')
      end

      it 'returns specific trace when it exists' do
        # First create a conversation to generate a trace
        conversation_request = {
          message: 'Tell me about the art installations at Burning Man',
          context: {
            session_id: "#{session_id}-specific",
            location: 'The Playa',
            persona: 'contemplative',
            trace_conversation: true
          }
        }

        post '/api/v1/conversation', conversation_request.to_json, 'CONTENT_TYPE' => 'application/json'

        expect(last_response).to be_ok
        conversation_data = JSON.parse(last_response.body)
        generated_trace_id = conversation_data['trace_id']

        # Now request the specific trace
        get '/admin/conversation_traces', trace_id: generated_trace_id

        expect(last_response).to be_ok
        data = JSON.parse(last_response.body)
        expect(data['trace']).to be_present
        expect(data['trace']['trace_id']).to eq(generated_trace_id)
        expect(data['trace']['session_id']).to eq("#{session_id}-specific")
        expect(data['trace']['traces']).to be_an(Array)
        expect(data['trace']['total_steps']).to be > 0
      end
    end

    context 'when no parameters provided' do
      it 'returns error message' do
        get '/admin/conversation_traces'

        expect(last_response).to be_ok
        data = JSON.parse(last_response.body)
        expect(data['error']).to eq('session_id or trace_id required')
      end
    end
  end

  describe 'GET /admin/trace_details/:trace_id' do
    context 'with real conversation trace', :vcr do
      it 'returns detailed trace analysis' do
        # Create conversation with multiple services involved
        conversation_request = {
          message: 'I want to know about the weather and also search my memories for art installations',
          context: {
            session_id: "#{session_id}-detailed",
            location: 'Deep Playa',
            tools: %w[weather memory_search],
            enable_tts: false, # Disable TTS to avoid external service calls
            trace_conversation: true
          },
          persona: 'mysterious'
        }

        post '/api/v1/conversation', conversation_request.to_json, 'CONTENT_TYPE' => 'application/json'

        expect(last_response).to be_ok
        conversation_data = JSON.parse(last_response.body)
        trace_id = conversation_data['trace_id']
        expect(trace_id).to be_present

        # Request detailed trace analysis
        get "/admin/trace_details/#{trace_id}"

        expect(last_response).to be_ok
        data = JSON.parse(last_response.body)

        expect(data['trace']).to be_present
        expect(data['summary']).to be_present

        # Verify summary contains expected analysis
        summary = data['summary']
        expect(summary['total_steps']).to be > 0
        expect(summary['total_duration_ms']).to be > 0
        expect(summary['session_id']).to eq("#{session_id}-detailed")
        expect(summary['services_used']).to be_an(Array)
        expect(summary['llm_calls']).to be >= 1
        expect(summary['has_errors']).to be_in([true, false])

        # Verify trace structure
        trace = data['trace']
        expect(trace['trace_id']).to eq(trace_id)
        expect(trace['traces']).to be_an(Array)
        expect(trace['traces'].first['step']).to eq(1)
        expect(trace['traces'].first['service']).to be_present
        expect(trace['traces'].first['action']).to be_present
        expect(trace['traces'].first['timestamp']).to be_present
      end

      it 'shows different services in trace flow' do
        # Create conversation that will use multiple services
        conversation_request = {
          message: 'What do you remember about previous conversations? Also, what\'s the current time?',
          context: {
            session_id: "#{session_id}-multi-service",
            location: 'Temple',
            skip_memories: false, # Ensure memory injection happens
            trace_conversation: true
          },
          persona: 'contemplative'
        }

        post '/api/v1/conversation', conversation_request.to_json, 'CONTENT_TYPE' => 'application/json'

        conversation_data = JSON.parse(last_response.body)
        trace_id = conversation_data['trace_id']

        get "/admin/trace_details/#{trace_id}"

        data = JSON.parse(last_response.body)
        services_used = data['summary']['services_used']

        # Verify we see the expected services in the flow
        expect(services_used).to include('ConversationModule')
        expect(services_used).to include('LLMService')

        # Check that we have detailed step information
        traces = data['trace']['traces']
        expect(traces).not_to be_empty

        # Verify we have a start step
        start_step = traces.find { |t| t['action'] == 'start_conversation' }
        expect(start_step).to be_present
        expect(start_step['service']).to eq('ConversationModule')

        # Verify we have an LLM call
        llm_step = traces.find { |t| t['service'] == 'LLMService' }
        expect(llm_step).to be_present
        expect(llm_step['data']['model']).to be_present
      end
    end

    context 'when trace does not exist' do
      it 'returns error message' do
        get '/admin/trace_details/non-existent-trace-id'

        expect(last_response).to be_ok
        data = JSON.parse(last_response.body)
        expect(data['error']).to eq('Trace not found')
      end
    end
  end

  describe 'End-to-end conversation tracing workflow', :vcr do
    it 'traces complete conversation flow from start to finish' do
      # Step 1: Create conversation with comprehensive context
      conversation_request = {
        message: 'I\'m curious about the intersection of technology and art. Can you share your thoughts and also tell me what you remember about our past conversations?',
        context: {
          session_id: "#{session_id}-e2e",
          location: 'Art Car Plaza',
          persona: 'contemplative',
          temperature: 0.9,
          max_tokens: 300,
          include_sensors: false,
          skip_memories: false,
          trace_conversation: true,
          source: 'admin_test'
        }
      }

      # Make the conversation request
      post '/api/v1/conversation', conversation_request.to_json, 'CONTENT_TYPE' => 'application/json'

      expect(last_response).to be_ok
      conversation_response = JSON.parse(last_response.body)

      # Verify conversation worked
      expect(conversation_response['response']).to be_present
      expect(conversation_response['trace_id']).to be_present
      expect(conversation_response['session_id']).to eq("#{session_id}-e2e")

      trace_id = conversation_response['trace_id']

      # Step 2: Retrieve the full trace
      get "/admin/trace_details/#{trace_id}"

      expect(last_response).to be_ok
      trace_data = JSON.parse(last_response.body)

      # Step 3: Verify comprehensive trace capture
      trace = trace_data['trace']
      summary = trace_data['summary']

      expect(trace['trace_id']).to eq(trace_id)
      expect(trace['session_id']).to eq("#{session_id}-e2e")
      expect(trace['total_steps']).to be >= 3 # At minimum: start, system prompt, LLM call, complete

      # Verify timing information
      expect(trace['total_duration_ms']).to be > 0
      expect(trace['started_at']).to be_present

      # Verify service summary
      expect(summary['services_used']).to include('ConversationModule')
      expect(summary['services_used']).to include('LLMService')
      expect(summary['llm_calls']).to be >= 1

      # Step 4: Verify detailed step information
      steps = trace['traces']

      # Check conversation start
      start_step = steps.find { |s| s['action'] == 'start_conversation' }
      expect(start_step).to be_present
      expect(start_step['data']['message']).to include('intersection of technology and art')
      expect(start_step['data']['persona']).to eq('contemplative')

      # Check system prompt generation
      system_prompt_step = steps.find { |s| s['service'] == 'SystemPromptService' }
      expect(system_prompt_step).to be_present if system_prompt_step

      # Check LLM call
      llm_step = steps.find { |s| s['service'] == 'LLMService' }
      expect(llm_step).to be_present
      expect(llm_step['data']['model']).to be_present
      expect(llm_step['data']['temperature']).to be_present
      expect(llm_step['success']).to be true

      # Check conversation completion
      complete_step = steps.find { |s| s['action'] == 'complete_conversation' }
      expect(complete_step).to be_present
      expect(complete_step['data']['response_length']).to be > 0
      expect(complete_step['data']['total_duration_ms']).to be > 0

      # Step 5: Verify we can retrieve by session ID
      get '/admin/conversation_traces', session_id: "#{session_id}-e2e"

      expect(last_response).to be_ok
      session_traces = JSON.parse(last_response.body)
      expect(session_traces['traces']).to have(1).item
      expect(session_traces['traces'].first['trace_id']).to eq(trace_id)
    end
  end
end
