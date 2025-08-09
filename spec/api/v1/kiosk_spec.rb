# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../app'

RSpec.describe 'Kiosk Interface API', type: :request do
  def app
    GlitchCubeApp
  end

  describe 'GET /kiosk' do
    it 'serves the kiosk web interface', :vcr do
      get '/kiosk'

      expect(last_response.status).to eq(200)
      expect(last_response.content_type).to include('text/html')
      expect(last_response.body).to include('Glitch Cube - Inner Mind')
      expect(last_response.body).to include('Current Persona')
      expect(last_response.body).to include('Inner Thoughts')
      expect(last_response.body).to include('Environment')
      expect(last_response.body).to include('Recent Interactions')
    end

    it 'includes CSS for mood-specific styling', :vcr do
      get '/kiosk'

      expect(last_response.body).to include('.mood-playful')
      expect(last_response.body).to include('.mood-contemplative')
      expect(last_response.body).to include('.mood-mysterious')
      expect(last_response.body).to include('.mood-neutral')
      expect(last_response.body).to include('.mood-offline')
    end

    it 'includes JavaScript for reactive updates', :vcr do
      get '/kiosk'

      expect(last_response.body).to include('KioskDisplay')
      expect(last_response.body).to include('/api/v1/kiosk/status')
      expect(last_response.body).to include('updateDisplay')
    end
  end

  describe 'GET /api/v1/kiosk/status' do
    let(:mock_ha_client) { instance_double(HomeAssistantClient) }

    before do
      allow(HomeAssistantClient).to receive(:new).and_return(mock_ha_client)

      # Reset KioskService state before each test
      Services::Kiosk::StateManager.reset!
    end

    context 'when all services are available' do
      before do
        mock_breaker = double('circuit_breaker')
        allow(mock_breaker).to receive(:call).and_yield
        allow(mock_ha_client).to receive(:states).and_return([
                                                               {
                                                                 'entity_id' => 'sensor.battery_level',
                                                                 'state' => '85',
                                                                 'attributes' => { 'unit_of_measurement' => '%' }
                                                               },
                                                               {
                                                                 'entity_id' => 'sensor.temperature',
                                                                 'state' => '22.5',
                                                                 'attributes' => { 'unit_of_measurement' => '°C' }
                                                               },
                                                               {
                                                                 'entity_id' => 'binary_sensor.motion',
                                                                 'state' => 'off'
                                                               },
                                                               {
                                                                 'entity_id' => 'light.glitch_cube',
                                                                 'state' => 'on',
                                                                 'attributes' => { 'brightness' => 255, 'rgb_color' => [255, 128, 0] }
                                                               }
                                                             ])

        allow(Services::CircuitBreakerService).to receive_messages(home_assistant_breaker: mock_breaker, status: [
                                                                     { name: 'home_assistant', state: :closed },
                                                                     { name: 'openrouter', state: :closed }
                                                                   ])
      end

      it 'returns comprehensive kiosk status', :vcr do
        get '/api/v1/kiosk/status'

        expect(last_response.status).to eq(200)
        json = JSON.parse(last_response.body)

        expect(json).to include(
          'persona' => hash_including(
            'current_mood' => 'neutral',
            'display_name' => 'Balanced Mind',
            'description' => 'Maintaining equilibrium while processing the world around me.'
          ),
          'inner_thoughts' => be_an(Array),
          'environment' => hash_including(
            'battery_level' => '85%',
            'temperature' => '22.5°C',
            'motion_detected' => false,
            'lighting_status' => hash_including('state' => 'on')
          ),
          'interactions' => hash_including(
            'recent' => [],
            'count_today' => 0
          ),
          'system_status' => hash_including(
            'overall_health' => 'healthy',
            'version' => be_a(String)
          ),
          'timestamp' => be_a(String)
        )
      end

      it 'includes mood-specific inner thoughts', :vcr do
        Services::KioskService.current_mood = 'playful'

        get '/api/v1/kiosk/status'

        json = JSON.parse(last_response.body)
        expect(json['inner_thoughts']).to include(
          match(/colors match today/)
        )
      end
    end

    context 'when Home Assistant is unavailable' do
      before do
        allow(Services::CircuitBreakerService).to receive(:home_assistant_breaker)
          .and_raise(CircuitBreaker::CircuitOpenError.new('HA unavailable'))

        allow(Services::CircuitBreakerService).to receive(:status).and_return([
                                                                                { name: 'home_assistant', state: :open },
                                                                                { name: 'openrouter', state: :closed }
                                                                              ])
      end

      it 'returns degraded status with fallback data', :vcr do
        get '/api/v1/kiosk/status'

        expect(last_response.status).to eq(200)
        json = JSON.parse(last_response.body)

        expect(json['environment']).to include('status' => 'circuit_open')
        expect(json['system_status']['overall_health']).to eq('degraded')
      end
    end

    context 'when system encounters general error' do
      before do
        allow(Services::CircuitBreakerService).to receive(:home_assistant_breaker)
          .and_raise(StandardError.new('General failure'))
      end

      it 'returns offline fallback state', :vcr do
        get '/api/v1/kiosk/status'

        expect(last_response.status).to eq(200)
        json = JSON.parse(last_response.body)

        expect(json['persona']['current_mood']).to eq('offline')
        expect(json['persona']['display_name']).to eq('System Offline')
        expect(json['inner_thoughts']).to include(
          'My systems are experiencing some turbulence...',
          'But my core essence remains vibrant',
          'Connection will return soon'
        )
      end
    end
  end

  describe 'KioskService integration with ConversationModule' do
    let(:conversation_module) { ConversationModule.new }

    before do
      # Reset state
      Services::Kiosk::StateManager.reset!
    end

    it 'updates kiosk display when conversation happens', :vcr do
      # Mock LLM service
      mock_response = instance_double(
        Services::LLMResponse,
        response_text: 'Hello there!',
        model: 'test-model',
        cost: 0.001,
        usage: { prompt_tokens: 10, completion_tokens: 20 },
        has_tool_calls?: false,
        continue_conversation?: true
      )

      allow(Services::LLMService).to receive(:complete_with_messages).and_return(mock_response)

      # Mock Home Assistant client for TTS and other calls
      mock_ha_client = double('HomeAssistantClient')
      allow(HomeAssistantClient).to receive(:new).and_return(mock_ha_client)
      allow(mock_ha_client).to receive_messages(speak: true, state: nil, call_service: true)

      allow(Services::LoggerService).to receive(:log_interaction)
      allow(Services::LoggerService).to receive(:log_tts)

      # Call conversation
      result = conversation_module.call(
        message: 'Hello, are you there?',
        context: { persona: 'playful' }
      )

      # Verify conversation worked
      expect(result[:response]).to eq('Hello there!')
      expect(result[:persona]).to eq('playful')

      # Check that kiosk was updated
      expect(Services::KioskService.current_mood).to eq('playful')
      expect(Services::KioskService.last_interaction).to include(
        message: 'Hello, are you there?',
        response: 'Hello there!'
      )
      expect(Services::KioskService.inner_thoughts).to include(
        'Just shared something meaningful with a visitor'
      )
    end
  end

  describe 'KioskService class methods' do
    before do
      Services::Kiosk::StateManager.reset!
    end

    it 'updates mood and adds corresponding thought', :vcr do
      Services::KioskService.update_mood('contemplative')

      expect(Services::KioskService.current_mood).to eq('contemplative')
      expect(Services::KioskService.inner_thoughts).to include(
        'Mood shifted to contemplative'
      )
    end

    it 'updates interaction data', :vcr do
      interaction_data = {
        message: 'Test message',
        response: 'Test response'
      }

      Services::KioskService.update_interaction(interaction_data)

      expect(Services::KioskService.last_interaction).to include(
        message: 'Test message',
        response: 'Test response',
        timestamp: be_a(String)
      )
    end

    it 'manages inner thoughts with limit of 5', :vcr do
      7.times { |i| Services::KioskService.add_inner_thought("Thought #{i}") }

      thoughts = Services::KioskService.inner_thoughts
      expect(thoughts.length).to eq(5)
      expect(thoughts).to include('Thought 6')
      expect(thoughts).not_to include('Thought 0', 'Thought 1')
    end
  end
end
