# frozen_string_literal: true

# Home Assistant Test Helpers
# Provides easy-to-use mocking helpers for Home Assistant integration tests
# Reduces boilerplate mocking code and ensures consistent test patterns
module HomeAssistantHelpers
  # Mock a successful Home Assistant service call
  # Usage: mock_ha_service_call('light.turn_on', entity_id: 'light.cube')
  def mock_ha_service_call(service_path, params = {}, response: { success: true })
    domain, service = service_path.split('.')

    mock_ha_client = instance_double(Core::HomeAssistantClient)
    allow(Core::HomeAssistantClient).to receive(:new).and_return(mock_ha_client)

    # Mock the call_service method
    allow(mock_ha_client).to receive(:call_service)
      .with(domain, service, params)
      .and_return(response)

    # Return the mock for further customization if needed
    mock_ha_client
  end

  # Mock Home Assistant entity state
  # Usage: mock_ha_entity_state('light.cube', 'on', brightness: 255)
  def mock_ha_entity_state(entity_id, state, attributes = {})
    mock_ha_client = instance_double(Core::HomeAssistantClient)
    allow(Core::HomeAssistantClient).to receive(:new).and_return(mock_ha_client)

    entity_data = {
      'entity_id' => entity_id,
      'state' => state,
      'attributes' => attributes.stringify_keys,
      'last_updated' => Time.now.iso8601
    }

    # Mock the state method for single entity
    allow(mock_ha_client).to receive(:state)
      .with(entity_id)
      .and_return(entity_data)

    # Mock the states method for bulk queries
    allow(mock_ha_client).to receive(:states)
      .and_return([entity_data])

    mock_ha_client
  end

  # Mock multiple entity states at once
  # Usage: mock_ha_entities({ 'light.cube' => { state: 'on', brightness: 255 } })
  def mock_ha_entities(entities_config)
    mock_ha_client = instance_double(Core::HomeAssistantClient)
    allow(Core::HomeAssistantClient).to receive(:new).and_return(mock_ha_client)

    states_data = entities_config.map do |entity_id, config|
      {
        'entity_id' => entity_id,
        'state' => config[:state] || config['state'] || 'unknown',
        'attributes' => (config[:attributes] || config['attributes'] || {}).stringify_keys,
        'last_updated' => Time.now.iso8601
      }
    end

    # Mock individual entity queries
    entities_config.each_key do |entity_id|
      entity_data = states_data.find { |s| s['entity_id'] == entity_id }
      allow(mock_ha_client).to receive(:state)
        .with(entity_id)
        .and_return(entity_data)
    end

    # Mock bulk states query
    allow(mock_ha_client).to receive(:states)
      .and_return(states_data)

    mock_ha_client
  end

  # Mock Home Assistant tool execution (for conversation tool calls)
  # Usage: mock_ha_tool_execution('turn_on_light', { entity_id: 'light.cube' })
  def mock_ha_tool_execution(tool_name, params = {}, success: true, result: nil)
    mock_result = if success
                    result || {
                      success: true,
                      entity_id: params[:entity_id] || params['entity_id'],
                      message: "#{tool_name} executed successfully"
                    }
                  else
                    {
                      success: false,
                      error: result || "#{tool_name} failed",
                      entity_id: params[:entity_id] || params['entity_id']
                    }
                  end

    # Mock the tool execution via Core::HomeAssistantClient
    mock_ha_client = instance_double(Core::HomeAssistantClient)
    allow(Core::HomeAssistantClient).to receive(:new).and_return(mock_ha_client)

    # Mock common tool execution patterns
    case tool_name
    when 'turn_on_light', 'turn_off_light'
      service = tool_name.include?('on') ? 'turn_on' : 'turn_off'
      allow(mock_ha_client).to receive(:call_service)
        .with('light', service, anything)
        .and_return(mock_result)
    when 'set_volume', 'pause_media', 'play_media'
      service = tool_name.sub('_media', '').sub('set_', '')
      allow(mock_ha_client).to receive(:call_service)
        .with('media_player', service, anything)
        .and_return(mock_result)
    else
      # Generic tool execution mock
      allow(mock_ha_client).to receive(:call_service)
        .and_return(mock_result)
    end

    mock_ha_client
  end

  # Mock Home Assistant conversation pipeline response
  # Usage: mock_ha_conversation_response('Hello there!', continue: true)
  def mock_ha_conversation_response(response_text, _continue: false, _actions: [])
    mock_ha_client = instance_double(Core::HomeAssistantClient)
    allow(Core::HomeAssistantClient).to receive(:new).and_return(mock_ha_client)

    response_data = {
      'conversation_id' => SecureRandom.uuid,
      'response' => {
        'speech' => {
          'plain' => {
            'speech' => response_text
          }
        },
        'response_type' => 'action_done'
      }
    }

    allow(mock_ha_client).to receive(:call_service)
      .with('conversation', 'process', anything)
      .and_return(response_data)

    mock_ha_client
  end

  # Mock TTS (text-to-speech) call
  # Usage: mock_ha_tts('Hello world', voice: 'openai')
  def mock_ha_tts(text, voice: 'openai', success: true)
    mock_ha_client = instance_double(Core::HomeAssistantClient)
    allow(Core::HomeAssistantClient).to receive(:new).and_return(mock_ha_client)

    result = success ? { success: true } : { success: false, error: 'TTS failed' }

    allow(mock_ha_client).to receive(:speak)
      .with(text, hash_including(voice: voice))
      .and_return(result)

    mock_ha_client
  end

  # Create a fully stubbed Home Assistant client with common methods
  # Usage: ha_client = stubbed_ha_client
  def stubbed_ha_client
    mock_ha_client = instance_double(Core::HomeAssistantClient)
    allow(Core::HomeAssistantClient).to receive(:new).and_return(mock_ha_client)

    # Stub common methods with reasonable defaults
    allow(mock_ha_client).to receive(:call_service).and_return({ success: true })
    allow(mock_ha_client).to receive(:state).and_return(nil)
    allow(mock_ha_client).to receive(:states).and_return([])
    allow(mock_ha_client).to receive(:speak).and_return(true)
    allow(mock_ha_client).to receive(:awtrix_display_text).and_return(true)
    allow(mock_ha_client).to receive(:awtrix_mood_light).and_return(true)
    allow(mock_ha_client).to receive(:set_state).and_return(true)

    mock_ha_client
  end

  # Helper to verify Home Assistant service calls were made
  # Usage: expect_ha_service_call('light', 'turn_on', entity_id: 'light.cube')
  def expect_ha_service_call(domain, service, params = {})
    expect_any_instance_of(Core::HomeAssistantClient)
      .to receive(:call_service)
      .with(domain, service, hash_including(params))
  end

  # Helper to verify TTS was called with specific text
  # Usage: expect_ha_tts('Hello world')
  def expect_ha_tts(text, voice: anything)
    expect_any_instance_of(Core::HomeAssistantClient)
      .to receive(:speak)
      .with(text, hash_including(voice: voice))
  end

  # Mock Home Assistant entity list for EntityManagerService
  # Usage: mock_ha_entity_list(lights: ['light.cube'], sensors: ['sensor.temp'])
  def mock_ha_entity_list(entity_groups = {})
    mock_ha_client = instance_double(Core::HomeAssistantClient)
    allow(Core::HomeAssistantClient).to receive(:new).and_return(mock_ha_client)

    all_entities = []

    entity_groups.each_value do |entity_ids|
      entity_ids.each do |entity_id|
        all_entities << {
          'entity_id' => entity_id,
          'state' => 'unknown',
          'attributes' => { 'friendly_name' => entity_id.split('.').last.humanize },
          'last_updated' => Time.now.iso8601
        }
      end
    end

    allow(mock_ha_client).to receive(:states).and_return(all_entities)

    mock_ha_client
  end
end

# Configure RSpec to include these helpers
if defined?(RSpec)
  RSpec.configure do |config|
    config.include HomeAssistantHelpers
  end
end
