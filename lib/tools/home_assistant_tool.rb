# frozen_string_literal: true

require 'httparty'
require 'json'

# Tool for interacting with Home Assistant
# Allows the AI to control lights, check sensors, and interact with the physical cube
class HomeAssistantTool
  def self.name
    'home_assistant'
  end

  def self.description
    'Control Home Assistant devices and check sensors. Args: action (string) - get_sensors, set_light, speak, or run_script; params (string) - JSON parameters for the action'
  end

  def self.call(action:, params: '{}')
    # Parse params if it's a string
    params = JSON.parse(params) if params.is_a?(String)

    # Use mock HA in development if enabled
    base_url = if GlitchCube.config.home_assistant.mock_enabled && !GlitchCube.config.test?
                 "http://localhost:#{GlitchCube.config.port}/mock_ha"
               elsif GlitchCube.config.home_assistant.mock_enabled && GlitchCube.config.test?
                 # In tests, we'll use a stub instead of HTTP calls
                 return mock_ha_response(action, params)
               else
                 GlitchCube.config.home_assistant.url
               end

    token = GlitchCube.config.home_assistant.mock_enabled ? 'mock-token-123' : GlitchCube.config.home_assistant.token

    return 'Error: Home Assistant not configured. Set HOME_ASSISTANT_URL and HOME_ASSISTANT_TOKEN in .env' unless base_url && token

    client = HomeAssistantClient.new(base_url: base_url, token: token)

    case action
    when 'get_sensors'
      get_all_sensors(client)
    when 'set_light'
      set_light_state(client, params)
    when 'speak'
      speak_message(client, params)
    when 'run_script'
      run_ha_script(client, params)
    else
      "Unknown action: #{action}. Available actions: get_sensors, set_light, speak, run_script"
    end
  rescue StandardError => e
    "Error: #{e.message}"
  end

  def self.mock_ha_response(action, params)
    case action
    when 'get_sensors'
      'Battery Level: 85%, Temperature: 22.5°C, Humidity: 45%, Light Level: 250lux, Motion Detector: off, Sound Level: 42dB'
    when 'set_light'
      entity_id = params['entity_id'] || 'light.glitch_cube'
      "Set #{entity_id} with brightness: #{params['brightness']}, color: #{params['rgb_color']}"
    when 'speak'
      message = params['message'] || 'Hello from Glitch Cube!'
      "Speaking: \"#{message}\""
    when 'run_script'
      script_name = params['script_name']
      "Executed script: #{script_name}"
    else
      "Unknown action: #{action}"
    end
  end

  def self.get_all_sensors(client)
    sensor_ids = %w[
      sensor.battery_level
      sensor.temperature
      sensor.humidity
      sensor.light_level
      binary_sensor.motion
      sensor.sound_level
    ]

    results = {}
    sensor_ids.each do |sensor_id|
      state = client.state(sensor_id)
      next unless state

      results[sensor_id] = {
        value: state['state'],
        unit: state.dig('attributes', 'unit_of_measurement'),
        friendly_name: state.dig('attributes', 'friendly_name')
      }
    end

    format_sensor_results(results)
  end

  def self.format_sensor_results(results)
    if results.empty?
      'No sensor data available'
    else
      results.map do |sensor, data|
        name = data[:friendly_name] || sensor
        value = data[:value]
        unit = data[:unit] || ''
        "#{name}: #{value}#{unit}"
      end.join(', ')
    end
  end

  def self.set_light_state(client, params)
    entity_id = params['entity_id'] || 'light.glitch_cube'

    if params['state'] == 'off'
      response = client.call_service('light', 'turn_off', { entity_id: entity_id })
      return "Turned off #{entity_id}" if response
    else
      # Turn on with optional parameters
      service_data = { entity_id: entity_id }
      service_data[:brightness] = params['brightness'] if params['brightness']
      service_data[:rgb_color] = params['rgb_color'] if params['rgb_color']
      service_data[:transition] = params['transition'] || 2

      response = client.call_service('light', 'turn_on', service_data)
      return "Set #{entity_id} with brightness: #{params['brightness']}, color: #{params['rgb_color']}" if response
    end

    'Failed to control light'
  end

  def self.speak_message(client, params)
    message = params['message'] || 'Hello from Glitch Cube!'
    entity_id = params['entity_id'] || 'media_player.glitch_cube_speaker'

    response = client.call_service('tts', 'google_translate_say', {
                                     entity_id: entity_id,
                                     message: message,
                                     language: 'en'
                                   })

    response ? "Speaking: \"#{message}\"" : 'Failed to speak message'
  end

  def self.run_ha_script(client, params)
    script_name = params['script_name']
    return 'Error: script_name required' unless script_name

    variables = params['variables'] || {}
    response = client.call_service('script', script_name, variables)

    response ? "Executed script: #{script_name}" : 'Failed to run script'
  end
end

# Use the main HomeAssistantClient from ../home_assistant_client.rb
require_relative '../home_assistant_client'
