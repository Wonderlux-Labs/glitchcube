# frozen_string_literal: true

# Shared contexts for Home Assistant testing
# Provides reusable test contexts for common HA scenarios
# Use with: include_context 'context_name'

# Define dummy services to allow mocking without loading the actual implementations
module Services
  # Placeholder for LLMService - will be mocked in tests
  # The real LLMService is autoloaded by Zeitwerk

  class PersonaStateService
    def self.get_current_persona
      'buddy'
    end

    def self.set_current_persona(persona)
      # This will be mocked in tests
    end
  end

  class SystemPromptService
    def generate
      'Test system prompt'
    end
  end

  class SimpleLogger
    def self.log_interaction(*args)
      # This will be mocked in tests
    end

    def self.log_tts(*args)
      # This will be mocked in tests
    end
  end

  module Logging
    class SimpleLogger
      def self.debug(*args)
        # This will be mocked in tests
      end

      def self.info(*args)
        # This will be mocked in tests
      end

      def self.log_error(*args)
        # This will be mocked in tests
      end
    end
  end

  class ConversationFeedbackService
    def set_state(state)
      # This will be mocked in tests
    end
  end

  class ConversationSideEffectHandler
    def initialize(*args); end

    def execute
      # This will be mocked in tests
    end
  end

  class ConversationErrorHandler
    def self.handle(*_args)
      # This will be mocked in tests
      {
        response: 'Error handled',
        error: 'Test error',
        session_id: 'test-session',
        persona: 'buddy',
        continue_conversation: false
      }
    end
  end

  class ToolExecutor
    def self.execute(tool_calls, _options = {})
      # This will be mocked in tests
      tool_calls.map { |_call| { success: true } }
    end
  end

  module Conversation
    class FlowManager
      def initialize(*args); end

      def process_conversation(*_args)
        # This will be mocked in tests
        {
          response: 'Default response',
          conversation_id: 'conv-123',
          session_id: 'test-session',
          persona: 'buddy',
          model: 'test-model',
          cost: 0.001,
          tokens: { prompt_tokens: 10, completion_tokens: 15 },
          continue_conversation: true,
          tts_handled: false,
          voice_interaction: false,
          error: nil
        }
      end
    end
  end
end

if defined?(RSpec)

  RSpec.shared_context 'with_home_assistant_stubbed' do
    let(:ha_client) { stubbed_ha_client }

    before do
      # Ensure all HA calls go through our stubbed client
      allow(HomeAssistantClient).to receive(:new).and_return(ha_client)
    end
  end

  RSpec.shared_context 'with_home_assistant_entities' do
    let(:mock_entities) do
      {
        'light.glitch_cube' => {
          state: 'on',
          attributes: { brightness: 255, color_mode: 'rgb', rgb_color: [255, 255, 255] }
        },
        'sensor.glitch_cube_temperature' => {
          state: '72',
          attributes: { unit_of_measurement: '°F', device_class: 'temperature' }
        },
        'sensor.glitch_cube_humidity' => {
          state: '45',
          attributes: { unit_of_measurement: '%', device_class: 'humidity' }
        },
        'binary_sensor.glitch_cube_motion' => {
          state: 'off',
          attributes: { device_class: 'motion' }
        },
        'media_player.square_voice' => {
          state: 'idle',
          attributes: { volume_level: 0.5, supported_features: 20_925 }
        },
        'device_tracker.glitch_cube' => {
          state: 'home',
          attributes: {
            latitude: 40.7831,
            longitude: -119.2034,
            gps_accuracy: 5,
            battery_level: 85
          }
        },
        'input_text.current_persona' => {
          state: 'buddy',
          attributes: { friendly_name: 'Current Persona' }
        }
      }
    end

    let(:ha_client) { mock_ha_entities(mock_entities) }

    before do
      allow(HomeAssistantClient).to receive(:new).and_return(ha_client)
    end
  end

  RSpec.shared_context 'with_lights_available' do
    let(:light_entities) do
      {
        'light.glitch_cube' => {
          state: 'on',
          attributes: {
            brightness: 255,
            color_mode: 'rgb',
            rgb_color: [255, 0, 0],
            supported_color_modes: %w[rgb brightness],
            friendly_name: 'Glitch Cube Main Light'
          }
        },
        'light.strip_1' => {
          state: 'off',
          attributes: {
            brightness: 0,
            supported_color_modes: %w[rgb brightness],
            friendly_name: 'LED Strip 1'
          }
        },
        'light.strip_2' => {
          state: 'off',
          attributes: {
            brightness: 0,
            supported_color_modes: %w[rgb brightness],
            friendly_name: 'LED Strip 2'
          }
        }
      }
    end

    let(:ha_client) { mock_ha_entities(light_entities) }

    before do
      allow(HomeAssistantClient).to receive(:new).and_return(ha_client)
    end
  end

  RSpec.shared_context 'with_sensors_responding' do
    let(:sensor_entities) do
      {
        'sensor.glitch_cube_temperature' => {
          state: '75.2',
          attributes: {
            unit_of_measurement: '°F',
            device_class: 'temperature',
            friendly_name: 'Cube Temperature'
          }
        },
        'sensor.glitch_cube_humidity' => {
          state: '42.1',
          attributes: {
            unit_of_measurement: '%',
            device_class: 'humidity',
            friendly_name: 'Cube Humidity'
          }
        },
        'sensor.glitch_cube_battery_level' => {
          state: '87',
          attributes: {
            unit_of_measurement: '%',
            device_class: 'battery',
            friendly_name: 'Cube Battery'
          }
        },
        'binary_sensor.glitch_cube_motion' => {
          state: 'off',
          attributes: {
            device_class: 'motion',
            friendly_name: 'Cube Motion'
          }
        }
      }
    end

    let(:ha_client) { mock_ha_entities(sensor_entities) }

    before do
      allow(HomeAssistantClient).to receive(:new).and_return(ha_client)
    end
  end

  RSpec.shared_context 'with_media_players_available' do
    let(:media_entities) do
      {
        'media_player.square_voice' => {
          state: 'idle',
          attributes: {
            volume_level: 0.5,
            is_volume_muted: false,
            supported_features: 20_925,
            friendly_name: 'Square Voice'
          }
        },
        'media_player.bluetooth_speaker' => {
          state: 'off',
          attributes: {
            volume_level: 0.3,
            supported_features: 20_925,
            friendly_name: 'Bluetooth Speaker'
          }
        }
      }
    end

    let(:ha_client) { mock_ha_entities(media_entities) }

    before do
      allow(HomeAssistantClient).to receive(:new).and_return(ha_client)
    end
  end

  RSpec.shared_context 'with_conversation_tools_available' do
    let(:ha_client) { stubbed_ha_client }

    before do
      allow(HomeAssistantClient).to receive(:new).and_return(ha_client)

      # Mock successful tool executions
      allow(ha_client).to receive(:call_service).and_return({ success: true })
      allow(ha_client).to receive(:speak).and_return(true)
      allow(ha_client).to receive(:awtrix_display_text).and_return(true)
      allow(ha_client).to receive(:awtrix_mood_light).and_return(true)
    end
  end

  RSpec.shared_context 'with_ha_service_failures' do
    let(:ha_client) { stubbed_ha_client }

    before do
      allow(HomeAssistantClient).to receive(:new).and_return(ha_client)

      # Mock service failures
      allow(ha_client).to receive(:call_service)
        .and_raise(StandardError.new('Home Assistant service unavailable'))
      allow(ha_client).to receive(:state)
        .and_raise(StandardError.new('Unable to fetch entity state'))
      allow(ha_client).to receive(:states)
        .and_raise(StandardError.new('Unable to fetch entity states'))
    end
  end

  RSpec.shared_context 'with_conversation_session' do
    let(:session_id) { 'test-session-123' }
    let(:conversation_context) do
      {
        session_id: session_id,
        visual_feedback: true,
        voice_interaction: true,
        persona: 'buddy'
      }
    end

    let(:mock_session) do
      instance_double(ConversationSession,
                      session_id: session_id,
                      messages_for_llm: [],
                      add_message: true,
                      messages: double('messages', count: 0),
                      created_at: Time.now - 1.minute,
                      metadata: {})
    end

    before do
      allow(ConversationSession).to receive(:find_or_create)
        .with(session_id: session_id, context: anything)
        .and_return(mock_session)
    end
  end

  RSpec.shared_context 'with_llm_service_mocked' do
    let(:mock_llm_response) do
      double('LLMResponse',
             response_text: 'Mock AI response from LLM',
             continue_conversation?: true,
             tool_calls?: false,
             has_tool_calls?: false,
             tool_calls: nil,
             function_calls: [],
             content: 'Mock AI response from LLM',
             parsed_content: {
               'response' => 'Mock AI response from LLM',
               'continue_conversation' => true
             }.with_indifferent_access,
             inner_thoughts: 'Test inner thoughts',
             cost: 0.001,
             model: 'test-model',
             usage: { prompt_tokens: 10, completion_tokens: 20 },
             message_data: {
               role: 'assistant',
               content: 'Mock AI response from LLM'
             })
    end

    before do
      allow(Services::Llm::LLMService).to receive(:complete_with_messages)
        .and_return(mock_llm_response)
    end
  end

  RSpec.shared_context 'with_circuit_breakers_reset' do
    before do
      # Reset all circuit breakers before test
      if defined?(Services::System::CircuitBreakerService) &&
         Services::System::CircuitBreakerService.respond_to?(:reset_all_breakers)
        Services::System::CircuitBreakerService.reset_all_breakers
      end
    end
  end

  RSpec.shared_context 'with_clean_redis' do
    before do
      redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379')
      redis.flushdb
      redis.quit
    rescue StandardError
      # Redis might not be available, that's fine
    end
  end

  # Composite context that sets up a full conversation environment
  RSpec.shared_context 'with_full_conversation_setup' do
    include_context 'with_home_assistant_entities'
    include_context 'with_conversation_session'
    include_context 'with_llm_service_mocked'
    include_context 'with_circuit_breakers_reset'
    include_context 'with_clean_redis'

    before do
      # Mock persona state service
      allow(Services::PersonaStateService).to receive(:get_current_persona)
        .and_return('buddy')

      # Mock system prompt service
      mock_prompt_service = instance_double(Services::Conversation::SystemPromptService)
      allow(Services::Conversation::SystemPromptService).to receive(:new)
        .and_return(mock_prompt_service)
      allow(mock_prompt_service).to receive(:generate)
        .and_return('Test system prompt for conversation')

      # Mock simple logger
      allow(Services::Logging::SimpleLogger).to receive(:debug)
      allow(Services::Logging::SimpleLogger).to receive(:info)
      allow(Services::Logging::SimpleLogger).to receive(:log_error)

      # Mock logger service
      allow(Services::Logging::SimpleLogger).to receive(:log_interaction)
      allow(Services::Logging::SimpleLogger).to receive(:log_tts)
    end
  end

end
