# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'

RSpec.describe GlitchCube::Routes::Development::Analytics do
  include Rack::Test::Methods

  def app
    GlitchCubeApp
  end

  # These routes should only be available in development/test
  describe 'route availability' do
    context 'in test environment' do
      it 'registers analytics routes' do
        # Just verify the routes work by calling them
        get '/api/v1/logs/errors'
        expect(last_response).to be_ok
        
        get '/api/v1/logs/circuit_breakers'
        expect(last_response).to be_ok
        
        get '/api/v1/analytics/conversations'
        expect(last_response).to be_ok
      end
    end
  end

  describe 'GET /api/v1/logs/errors' do
    let(:error_summary) { { total_errors: 5, recent_errors: 2 } }
    let(:error_stats) { [{ error: 'Connection timeout', count: 3 }] }

    before do
      allow(Services::LoggerService).to receive_messages(error_summary: error_summary, error_stats: error_stats)
    end

    it 'returns error statistics' do
      get '/api/v1/logs/errors'

      expect(last_response).to be_ok
      expect(last_response.content_type).to include('application/json')

      body = JSON.parse(last_response.body)
      expect(body['error_summary']).to eq({ 'total_errors' => 5, 'recent_errors' => 2 })
      expect(body['error_stats']).to eq([{ 'error' => 'Connection timeout', 'count' => 3 }])
    end
  end

  describe 'GET /api/v1/logs/circuit_breakers' do
    let(:circuit_status) do
      [
        { name: 'openrouter', state: :closed, failure_count: 0 },
        { name: 'home_assistant', state: :open, failure_count: 5 }
      ]
    end

    before do
      allow(Services::CircuitBreakerService).to receive(:status).and_return(circuit_status)
    end

    it 'returns circuit breaker status with action endpoints' do
      get '/api/v1/logs/circuit_breakers'

      expect(last_response).to be_ok

      body = JSON.parse(last_response.body)
      expect(body['circuit_breakers']).to eq([
                                               { 'name' => 'openrouter', 'state' => 'closed', 'failure_count' => 0 },
                                               { 'name' => 'home_assistant', 'state' => 'open', 'failure_count' => 5 }
                                             ])
      expect(body['actions']['reset_all']).to eq('/api/v1/logs/circuit_breakers/reset')
      expect(body['actions']['reset_single']).to eq('/api/v1/logs/circuit_breakers/:name/reset')
    end
  end

  describe 'POST /api/v1/logs/circuit_breakers/reset' do
    before do
      allow(Services::CircuitBreakerService).to receive(:reset_all)
    end

    it 'resets all circuit breakers' do
      post '/api/v1/logs/circuit_breakers/reset'

      expect(last_response).to be_ok

      body = JSON.parse(last_response.body)
      expect(body['message']).to eq('All circuit breakers reset')
      expect(body['status']).to eq('success')

      expect(Services::CircuitBreakerService).to have_received(:reset_all)
    end
  end

  describe 'GET /api/v1/analytics/conversations' do
    before do
      # Create test conversation sessions
      require_relative '../../../../lib/services/conversation_session'
      
      # Clear existing sessions
      Conversation.destroy_all
      Message.destroy_all
      
      # Create test sessions with messages
      conversation1 = Conversation.create!(
        session_id: 'abc123',
        persona: 'playful',
        started_at: Time.current
      )
      conversation1.messages.create!(
        role: 'user',
        content: 'Hello'
      )
      conversation1.messages.create!(
        role: 'assistant',
        content: 'Hi there!'
      )
      
      conversation2 = Conversation.create!(
        session_id: 'def456',
        persona: 'buddy',
        started_at: Time.current
      )
      conversation2.messages.create!(
        role: 'user',
        content: 'How are you?'
      )
    end

    it 'returns conversation analytics with default limit' do
      get '/api/v1/analytics/conversations'

      expect(last_response).to be_ok

      body = JSON.parse(last_response.body)
      expect(body['success']).to be true
      expect(body['count']).to eq(2)
      expect(body['conversations']).to be_an(Array)
      expect(body['conversations'].first).to include('session_id', 'started_at', 'message_count')
    end

    it 'accepts custom limit parameter' do
      get '/api/v1/analytics/conversations?limit=1'
      
      body = JSON.parse(last_response.body)
      expect(body['count']).to eq(1)
    end
  end

  describe 'GET /api/v1/system_prompt/:character?' do
    let(:system_prompt_service) { instance_double(Services::SystemPromptService) }
    let(:generated_prompt) { 'You are Glitch Cube, an art installation...' }

    before do
      allow(Services::SystemPromptService).to receive(:new).and_return(system_prompt_service)
      allow(system_prompt_service).to receive(:generate).and_return(generated_prompt)
    end

    it 'returns system prompt for default character' do
      get '/api/v1/system_prompt'

      expect(last_response).to be_ok

      body = JSON.parse(last_response.body)
      expect(body['success']).to be true
      expect(body['character']).to eq('default')
      expect(body['prompt']).to eq(generated_prompt)
      expect(body).to have_key('timestamp')
    end

    it 'returns system prompt for specific character' do
      get '/api/v1/system_prompt/playful'

      expect(last_response).to be_ok

      body = JSON.parse(last_response.body)
      expect(body['character']).to eq('playful')

      expect(Services::SystemPromptService).to have_received(:new).with(
        character: 'playful',
        context: hash_including(
          location: 'Default Location',
          battery_level: '100%',
          interaction_count: 1
        )
      )
    end

    it 'accepts context parameters' do
      get '/api/v1/system_prompt/mysterious?location=Temple&battery=75&count=5'

      expect(Services::SystemPromptService).to have_received(:new).with(
        character: 'mysterious',
        context: hash_including(
          location: 'Temple',
          battery_level: '75',
          interaction_count: 5
        )
      )
    end
  end

  describe 'GET /api/v1/analytics/modules/:module_name' do
    it 'returns analytics for specific module' do
      get '/api/v1/analytics/modules/conversation_module'

      expect(last_response).to be_ok

      body = JSON.parse(last_response.body)
      expect(body['success']).to be true
      expect(body['module']).to eq('conversation_module')
      expect(body['analytics']).to include('status', 'placeholder_data')
      expect(body['analytics']['status']).to eq('Module analytics not yet implemented')
    end
  end

  describe 'context document management' do
    let(:context_service) { instance_double(Services::ContextRetrievalService) }

    before do
      allow(Services::ContextRetrievalService).to receive(:new).and_return(context_service)
    end

    describe 'GET /api/v1/context/documents' do
      let(:documents) do
        [
          { 'filename' => 'installation_guide.txt', 'metadata' => { 'type' => 'guide' } },
          { 'filename' => 'character_prompts.txt', 'metadata' => { 'type' => 'prompts' } }
        ]
      end

      before do
        allow(context_service).to receive(:list_documents).and_return(documents)
      end

      it 'returns list of context documents' do
        get '/api/v1/context/documents'

        expect(last_response).to be_ok

        body = JSON.parse(last_response.body)
        expect(body['success']).to be true
        expect(body['documents']).to eq(documents)
      end
    end

    describe 'POST /api/v1/context/documents' do
      before do
        allow(context_service).to receive(:add_document).and_return(true)
      end

      it 'adds new context document' do
        document_data = {
          filename: 'new_guide.txt',
          content: 'This is a guide...',
          metadata: { type: 'guide', author: 'curator' }
        }

        post '/api/v1/context/documents',
             document_data.to_json,
             { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response).to be_ok

        body = JSON.parse(last_response.body)
        expect(body['success']).to be true
        expect(body['message']).to eq('Document added successfully')

        expect(context_service).to have_received(:add_document).with(
          'new_guide.txt',
          'This is a guide...',
          { 'type' => 'guide', 'author' => 'curator' }
        )
      end

      it 'handles missing metadata gracefully' do
        document_data = {
          filename: 'simple.txt',
          content: 'Simple content'
        }

        post '/api/v1/context/documents',
             document_data.to_json,
             { 'CONTENT_TYPE' => 'application/json' }

        expect(context_service).to have_received(:add_document).with(
          'simple.txt',
          'Simple content',
          {}
        )
      end

      it 'handles service errors' do
        allow(context_service).to receive(:add_document).and_raise(StandardError, 'Storage failed')

        post '/api/v1/context/documents',
             { filename: 'test.txt', content: 'test' }.to_json,
             { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response.status).to eq(400)

        body = JSON.parse(last_response.body)
        expect(body['success']).to be false
        expect(body['error']).to eq('Storage failed')
      end
    end

    describe 'POST /api/v1/context/search' do
      let(:search_results) do
        [
          { content: 'Relevant info about installation...', score: 0.9 },
          { content: 'Additional context...', score: 0.7 }
        ]
      end

      before do
        allow(context_service).to receive(:retrieve_context).and_return(search_results)
      end

      it 'searches context documents' do
        search_data = { query: 'installation guide', k: 3 }

        post '/api/v1/context/search',
             search_data.to_json,
             { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response).to be_ok

        body = JSON.parse(last_response.body)
        expect(body['success']).to be true
        expect(body['query']).to eq('installation guide')
        expect(body['results']).to eq(search_results.map(&:stringify_keys))

        expect(context_service).to have_received(:retrieve_context).with('installation guide', k: 3)
      end

      it 'uses default k value when not provided' do
        search_data = { query: 'test query' }

        post '/api/v1/context/search',
             search_data.to_json,
             { 'CONTENT_TYPE' => 'application/json' }

        expect(context_service).to have_received(:retrieve_context).with('test query', k: 3)
      end
    end
  end
end
