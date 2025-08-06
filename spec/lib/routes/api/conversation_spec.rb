# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'

RSpec.describe GlitchCube::Routes::Api::Conversation, :failing do
  include Rack::Test::Methods

  def app
    GlitchCubeApp
  end

  let(:conversation_handler_service) { instance_double(Services::ConversationHandlerService) }
  let(:conversation_module) { double('conversation_module') }

  before do
    allow(Services::ConversationHandlerService).to receive(:new).and_return(conversation_handler_service)
    allow(conversation_handler_service).to receive(:conversation_module).and_return(conversation_module)
  end

  describe 'POST /api/v1/test' do
    let(:mock_response) do
      {
        response: 'Hello from Glitch Cube!',
        suggested_mood: 'friendly',
        confidence: 0.9
      }
    end

    before do
      allow(conversation_module).to receive(:call).and_return(mock_response)
    end

    it 'processes basic conversation requests' do
      post '/api/v1/test',
           { message: 'Hello, Glitch Cube!' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response).to be_ok
      expect(last_response.content_type).to include('application/json')

      body = JSON.parse(last_response.body)
      expect(body['success']).to be true
      expect(body['response']).to eq('Hello from Glitch Cube!')
      expect(body).to have_key('timestamp')
    end

    it 'uses default message when none provided' do
      post '/api/v1/test',
           {}.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response).to be_ok

      expect(conversation_module).to have_received(:call).with(
        message: 'Hello, Glitch Cube!',
        context: {}
      )
    end

    it 'handles errors gracefully' do
      allow(conversation_module).to receive(:call).and_raise(StandardError, 'Test error')

      post '/api/v1/test',
           { message: 'Test message' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(500)

      body = JSON.parse(last_response.body)
      expect(body['success']).to be false
      expect(body['error']).to eq('Test error')
    end
  end

  describe 'POST /api/v1/conversation' do
    let(:mock_response) do
      {
        response: 'Great conversation!',
        suggested_mood: 'engaged',
        confidence: 0.95,
        continue_conversation: true,
        actions: ['turn_light_blue'],
        media_actions: []
      }
    end

    before do
      allow(conversation_handler_service).to receive(:process_conversation).and_return(mock_response)
      allow(SecureRandom).to receive(:uuid).and_return('test-session-id')
    end

    it 'processes full conversation with HA integration' do
      post '/api/v1/conversation',
           { 
             message: 'Turn the light blue and tell me about the weather',
             mood: 'curious',
             context: { voice_interaction: true }
           }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response).to be_ok
      
      body = JSON.parse(last_response.body)
      expect(body['success']).to be true
      expect(body['data']['response']).to eq('Great conversation!')
      expect(body['data']['actions']).to eq(['turn_light_blue'])
      expect(body['data']['continue_conversation']).to be true
    end

    it 'generates session ID when not provided' do
      post '/api/v1/conversation',
           { message: 'Hello' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(conversation_handler_service).to have_received(:process_conversation).with(
        message: 'Hello',
        context: hash_including(session_id: 'test-session-id'),
        mood: 'neutral'
      )
    end

    it 'preserves existing session ID' do
      env 'rack.session', { session_id: 'existing-session' }
      
      post '/api/v1/conversation',
           { 
             message: 'Continue conversation',
             context: { session_id: 'existing-session' }
           }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(conversation_handler_service).to have_received(:process_conversation).with(
        message: 'Continue conversation',
        context: hash_including(session_id: 'existing-session'),
        mood: 'neutral'
      )
    end

    it 'handles voice interaction context' do
      post '/api/v1/conversation',
           { 
             message: 'Hello',
             context: {
               voice_interaction: true,
               device_id: 'cube_speaker',
               conversation_id: 'voice_123',
               language: 'en'
             }
           }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(conversation_handler_service).to have_received(:process_conversation).with(
        message: 'Hello',
        context: hash_including(
          'voice_interaction' => true,
          'device_id' => 'cube_speaker',
          'conversation_id' => 'voice_123',
          'language' => 'en'
        ),
        mood: 'neutral'
      )
    end
  end

  describe 'POST /api/v1/conversation/with_context' do
    let(:rag_service) { instance_double(Services::SimpleRAG) }
    let(:rag_result) do
      {
        contexts_used: ['Weather data', 'Location info'],
        confidence: 0.8
      }
    end
    let(:conv_result) do
      {
        response: 'Enhanced response with context',
        suggested_mood: 'informative',
        confidence: 0.9
      }
    end

    before do
      allow(Services::SimpleRAG).to receive(:new).and_return(rag_service)
      allow(rag_service).to receive(:answer_with_context).and_return(rag_result)
      allow(conversation_module).to receive(:call).and_return(conv_result)
    end

    it 'enhances conversation with RAG context' do
      post '/api/v1/conversation/with_context',
           { message: 'What is the weather like?' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response).to be_ok

      body = JSON.parse(last_response.body)
      expect(body['success']).to be true
      expect(body['data']['response']).to eq('Enhanced response with context')
      expect(body['data']['contexts_used']).to eq(['Weather data', 'Location info'])
      expect(body['data']['confidence']).to eq(0.9) # Max of conv and rag confidence
    end

    it 'uses RAG service to retrieve context' do
      post '/api/v1/conversation/with_context',
           { message: 'Tell me about the installation' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(rag_service).to have_received(:answer_with_context).with('Tell me about the installation')
    end
  end

  describe 'POST /api/v1/conversation/start' do
    let(:proactive_message) { 'Hello! I noticed someone approaching. How can I help you today?' }

    before do
      allow(conversation_handler_service).to receive(:generate_proactive_message).and_return(proactive_message)
      allow(conversation_handler_service).to receive(:send_conversation_to_ha).and_return({ success: true })
    end

    it 'generates proactive conversation starters' do
      post '/api/v1/conversation/start',
           { 
             trigger: 'motion_detected',
             context: { location: 'main_area', time_of_day: 'evening' }
           }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response).to be_ok

      body = JSON.parse(last_response.body)
      expect(body['success']).to be true
      expect(body['data']['message']).to eq(proactive_message)
      expect(body['data']['ha_response']).to eq({ 'success' => true })

      expect(conversation_handler_service).to have_received(:generate_proactive_message).with(
        'motion_detected',
        { 'location' => 'main_area', 'time_of_day' => 'evening' }
      )
    end

    it 'uses custom message when provided' do
      custom_message = 'Welcome to the playa!'
      
      post '/api/v1/conversation/start',
           { message: custom_message }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response).to be_ok

      body = JSON.parse(last_response.body)
      expect(body['data']['message']).to eq(custom_message)

      expect(conversation_handler_service).not_to have_received(:generate_proactive_message)
    end

    it 'defaults to automation trigger when none specified' do
      post '/api/v1/conversation/start',
           {}.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(conversation_handler_service).to have_received(:generate_proactive_message).with(
        'automation',
        {}
      )
    end
  end
end