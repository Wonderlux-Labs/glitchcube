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
      it 'registers analytics routes', :pending do
        expect(app.routes['GET']).to include(
          /^\/api\/v1\/logs\/errors$/,
          /^\/api\/v1\/logs\/circuit_breakers$/,
          /^\/api\/v1\/analytics\/conversations$/
        )
      end
    end
  end

  describe 'GET /api/v1/logs/errors' do
    let(:error_summary) { { total_errors: 5, recent_errors: 2 } }
    let(:error_stats) { [{ error: 'Connection timeout', count: 3 }] }

    before do
      allow(Services::LoggerService).to receive(:error_summary).and_return(error_summary)
      allow(Services::LoggerService).to receive(:error_stats).and_return(error_stats)
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
    let(:conversation_history) do
      [
        { id: 1, message: 'Hello', response: 'Hi there!', timestamp: Time.now.iso8601 },
        { id: 2, message: 'How are you?', response: 'I\'m doing well!', timestamp: Time.now.iso8601 }
      ]
    end

    before do
      allow(GlitchCube::Persistence).to receive(:get_conversation_history).and_return(conversation_history)
    end

    it 'returns conversation analytics with default limit', :pending do
      get '/api/v1/analytics/conversations'

      expect(last_response).to be_ok

      body = JSON.parse(last_response.body)
      expect(body['success']).to be true
      expect(body['count']).to eq(2)
      expect(body['conversations']).to eq(conversation_history.map(&:stringify_keys))

      expect(GlitchCube::Persistence).to have_received(:get_conversation_history).with(limit: 10)
    end

    it 'accepts custom limit parameter', :pending do
      get '/api/v1/analytics/conversations?limit=5'

      expect(GlitchCube::Persistence).to have_received(:get_conversation_history).with(limit: 5)
    end
  end

  describe 'GET /api/v1/system_prompt/:character?' do
    let(:system_prompt_service) { instance_double(Services::SystemPromptService) }
    let(:generated_prompt) { 'You are Glitch Cube, an art installation...' }

    before do
      allow(Services::SystemPromptService).to receive(:new).and_return(system_prompt_service)
      allow(system_prompt_service).to receive(:generate).and_return(generated_prompt)
    end

    it 'returns system prompt for default character', :pending do
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
    let(:module_analytics) do
      { 
        total_calls: 50,
        average_response_time: 1.2,
        success_rate: 0.95
      }
    end

    before do
      allow(GlitchCube::Persistence).to receive(:get_module_analytics).and_return(module_analytics)
    end

    it 'returns analytics for specific module', :pending do
      get '/api/v1/analytics/modules/conversation_module'

      expect(last_response).to be_ok

      body = JSON.parse(last_response.body)
      expect(body['success']).to be true
      expect(body['module']).to eq('conversation_module')
      expect(body['analytics']).to eq(module_analytics.stringify_keys)

      expect(GlitchCube::Persistence).to have_received(:get_module_analytics).with('conversation_module')
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

  describe 'beacon management' do
    let(:beacon_service) { instance_double(Services::BeaconService) }

    before do
      allow(Services::BeaconService).to receive(:new).and_return(beacon_service)
    end

    describe 'GET /api/v1/beacon/status' do
      before do
        allow(GlitchCube.config.redis_connection).to receive(:get).with('beacon:last_heartbeat').and_return('2024-08-05T12:00:00Z')
      end

      it 'returns beacon status information' do
        get '/api/v1/beacon/status'

        expect(last_response).to be_ok

        body = JSON.parse(last_response.body)
        expect(body['success']).to be true
        expect(body['beacon_enabled']).to be_in([true, false])
        expect(body['last_heartbeat']).to eq('2024-08-05T12:00:00Z')
        expect(body['device_id']).to be_a(String)
        expect(body['location']).to be_a(String)
      end
    end

    describe 'POST /api/v1/beacon/send' do
      before do
        allow(beacon_service).to receive(:send_heartbeat).and_return(true)
        allow(GlitchCube.config.redis_connection).to receive(:set)
      end

      it 'sends heartbeat via beacon service' do
        post '/api/v1/beacon/send'

        expect(last_response).to be_ok

        body = JSON.parse(last_response.body)
        expect(body['success']).to be true
        expect(body).to have_key('timestamp')

        expect(beacon_service).to have_received(:send_heartbeat)
      end
    end

    describe 'POST /api/v1/beacon/alert' do
      before do
        allow(beacon_service).to receive(:send_alert)
      end

      it 'sends alert via beacon service' do
        alert_data = { message: 'Low battery warning', level: 'warning' }

        post '/api/v1/beacon/alert',
             alert_data.to_json,
             { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response).to be_ok

        body = JSON.parse(last_response.body)
        expect(body['success']).to be true
        expect(body['message']).to eq('Alert sent')

        expect(beacon_service).to have_received(:send_alert).with('Low battery warning', 'warning')
      end

      it 'uses default level when not provided' do
        alert_data = { message: 'System status update' }

        post '/api/v1/beacon/alert',
             alert_data.to_json,
             { 'CONTENT_TYPE' => 'application/json' }

        expect(beacon_service).to have_received(:send_alert).with('System status update', 'info')
      end
    end
  end
end