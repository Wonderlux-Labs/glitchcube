# frozen_string_literal: true

require 'spec_helper'
require 'rspec'
require 'rack/test'

# Phase 3.5: Simple Session Management Integration Tests
#
# Testing simplified session model:
# - New session for every conversation start (voice trigger, automation, etc.)
# - Continuation controlled by end_conversation flag from Sinatra
# - LED/sound feedback hooks integrated with conversation states
# - No complex timeout or session management logic

RSpec.describe 'Simple Session Management - Phase 3.5', type: :integration do
  include Rack::Test::Methods

  def app
    GlitchCubeApp
  end

  describe 'New Session Creation' do
    it 'creates new session for each conversation start' do
      VCR.use_cassette('simple_session_new_conversation') do
        # Simulate voice trigger starting new conversation
        session_id_1 = "voice_#{Time.now.to_i}_#{rand(1000..9999)}"

        post '/api/v1/conversation', {
          message: 'Turn on the lights',
          context: {
            session_id: session_id_1,
            voice_interaction: true,
            new_session: true,
            device_id: 'glitchcube_satellite'
          }
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(200)
        response_data = JSON.parse(last_response.body)

        expect(response_data['success']).to be true
        expect(response_data['data']['session_id']).to eq(session_id_1)
        expect(response_data['data']['response']).to be_present

        # Should have continuation flag
        expect(response_data['data']).to have_key('end_conversation')

        # Second conversation start should create different session
        session_id_2 = "voice_#{Time.now.to_i + 1}_#{rand(1000..9999)}"

        post '/api/v1/conversation', {
          message: "What's the weather like?",
          context: {
            session_id: session_id_2,
            voice_interaction: true,
            new_session: true,
            device_id: 'glitchcube_satellite'
          }
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(200)
        response_data_2 = JSON.parse(last_response.body)

        # Different session IDs confirm new sessions
        expect(response_data_2['data']['session_id']).to eq(session_id_2)
        expect(response_data_2['data']['session_id']).not_to eq(session_id_1)
      end
    end
  end

  describe 'Conversation Continuation Logic' do
    it 'uses HA conversation_id to track sessions - same ID = continuation, new ID = new session' do
      VCR.use_cassette('simple_session_full_flow') do
        # CONVERSATION 1: Wake word triggers new HA conversation
        # HA generates its own conversation_id - we just use it
        ha_conversation_id_1 = 'abc123' # What HA actually sends
        session_id_1 = "voice_#{ha_conversation_id_1}"

        # First message (wake word triggered this)
        post '/api/v1/conversation', {
          message: 'Hello, can you turn on the lights?',
          context: {
            session_id: session_id_1, # We derive this from HA's conversation_id
            conversation_id: ha_conversation_id_1, # HA provides this
            voice_interaction: true,
            device_id: 'glitchcube_satellite'
          }
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        response_1 = JSON.parse(last_response.body)
        expect(response_1['success']).to be true
        stored_session_1 = response_1['data']['session_id'] # Whatever Sinatra decides to use
        expect(response_1['data']['end_conversation']).to be_falsy # LLM decides to continue

        # CONVERSATION 1: HA kept listening (because end_conversation was false)
        # So it sends the SAME conversation_id
        post '/api/v1/conversation', {
          message: 'And make them blue please',
          context: {
            session_id: session_id_1, # Same session ID from HA
            conversation_id: ha_conversation_id_1, # SAME HA conversation_id
            voice_interaction: true,
            device_id: 'glitchcube_satellite'
          }
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        response_2 = JSON.parse(last_response.body)
        stored_session_2 = response_2['data']['session_id']
        expect(stored_session_2).to eq(stored_session_1) # Should maintain same session
        expect(response_2['data']['response']).to be_present

        # CONVERSATION 1: Natural ending
        post '/api/v1/conversation', {
          message: "Thanks, that's perfect",
          context: {
            session_id: session_id_1,
            conversation_id: ha_conversation_id_1,
            voice_interaction: true,
            device_id: 'glitchcube_satellite'
          }
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        response_3 = JSON.parse(last_response.body)
        expect(response_3['data']['session_id']).to eq(session_id_1)
        # AI might end conversation after acknowledgment
        # (depends on LLM decision based on context)

        # CONVERSATION 2: New wake word = HA creates NEW conversation_id
        ha_conversation_id_2 = 'xyz789' # Different ID from HA
        session_id_2 = "voice_#{ha_conversation_id_2}"

        post '/api/v1/conversation', {
          message: "What's the weather like?",
          context: {
            session_id: session_id_2, # New session based on new HA conversation_id
            conversation_id: ha_conversation_id_2, # NEW HA conversation_id
            voice_interaction: true,
            device_id: 'glitchcube_satellite'
          }
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        response_4 = JSON.parse(last_response.body)
        stored_session_4 = response_4['data']['session_id']
        expect(stored_session_4).not_to eq(stored_session_1) # Different from first conversation
        expect(response_4['data']['response']).to be_present
      end
    end

    it 'ends conversation when end_conversation is true' do
      VCR.use_cassette('simple_session_end_conversation') do
        session_id = "voice_#{Time.now.to_i}_#{rand(1000..9999)}"

        post '/api/v1/conversation', {
          message: 'Goodbye',
          context: {
            session_id: session_id,
            voice_interaction: true,
            new_session: true
          }
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        response_data = JSON.parse(last_response.body)

        # Should end conversation for goodbye messages
        expect(response_data['data']['end_conversation']).to be_truthy
        expect(response_data['data']['response']).to include_any_of(['goodbye', 'bye', 'farewell', 'see you'])
      end
    end
  end

  describe 'Feedback Hooks Integration' do
    it 'provides feedback state information in response' do
      VCR.use_cassette('simple_session_feedback_hooks') do
        session_id = "voice_#{Time.now.to_i}_#{rand(1000..9999)}"

        post '/api/v1/conversation', {
          message: 'Turn on the party lights',
          context: {
            session_id: session_id,
            voice_interaction: true,
            new_session: true,
            visual_feedback: true,
            tools: [
              {
                'type' => 'function',
                'function' => {
                  'name' => 'conversation_feedback',
                  'description' => 'LED feedback control'
                }
              }
            ]
          }
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(200)
        response_data = JSON.parse(last_response.body)

        # Should have feedback information
        expect(response_data['data']).to have_key('session_id')
        expect(response_data['data']).to have_key('response')
        expect(response_data['data']).to have_key('end_conversation')
      end
    end
  end

  describe 'Voice Interaction Context' do
    it 'handles voice-specific context correctly' do
      VCR.use_cassette('simple_session_voice_context') do
        session_id = "voice_#{Time.now.to_i}_#{rand(1000..9999)}"

        post '/api/v1/conversation', {
          message: 'What time is it?',
          context: {
            session_id: session_id,
            voice_interaction: true,
            new_session: true,
            device_id: 'glitchcube_satellite',
            language: 'en',
            # Simulate HA conversation context
            ha_context: {
              agent_id: 'glitchcube_conversation',
              user_id: 'voice_user'
            }
          }
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(200)
        response_data = JSON.parse(last_response.body)

        expect(response_data['success']).to be true
        expect(response_data['data']['session_id']).to eq(session_id)
        expect(response_data['data']['response']).to be_present
      end
    end
  end
end

# Helper matcher for flexible response checking
RSpec::Matchers.define :include_any_of do |expected|
  match do |actual|
    expected.any? { |word| actual.downcase.include?(word.downcase) }
  end

  failure_message do |actual|
    "expected '#{actual}' to include any of #{expected}"
  end
end
