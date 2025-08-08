# frozen_string_literal: true

require 'httparty'
require 'json'
require_relative 'base_tool'

# Tool for interacting with Home Assistant
# Allows the AI to control lights, check sensors, and interact with the physical cube
class HomeAssistantTool < BaseTool
  def self.name
    'home_assistant'
  end

  def self.description
    'Control Home Assistant devices and check sensors. For sensor readings use action: "get_sensors". For lights use action: "set_light" with params like {"brightness": 50, "rgb_color": [255,0,0]}. For speaking use action: "speak" with params {"message": "text"}. Args: action (string), params (string) - JSON parameters'
  end

  def self.parameters
    {
      'action' => {
        type: 'string',
        description: 'Action to perform',
        enum: %w[get_sensors set_light speak run_script]
      },
      'params' => {
        type: 'object',
        description: 'Parameters for the action (JSON object)'
      }
    }
  end

  def self.required_parameters
    %w[action]
  end

  def self.category
    'system_integration'
  end

  def self.call(action:, params: '{}')
    validate_required_params({ 'action' => action }, ['action'])
    params = parse_json_params(params)

    case action
    when 'get_sensors'
      get_all_sensors
    when 'set_light'
      set_light_state(params)
    when 'speak'
      speak_message(params)
    when 'run_script'
      run_ha_script(params)
    else
      format_response(false, "Unknown action: #{action}. Available actions: get_sensors, set_light, speak, run_script")
    end
  rescue ValidationError => e
    format_response(false, "Validation error: #{e.message}")
  rescue StandardError => e
    format_response(false, "Error: #{e.message}")
  end

  def self.get_all_sensors
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
      state = get_ha_state(sensor_id)
      next unless state.is_a?(Hash)

      results[sensor_id] = {
        value: state[:state],
        unit: state[:attributes]['unit_of_measurement'],
        friendly_name: state[:attributes]['friendly_name']
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

  def self.set_light_state(params)
    entity_id = params['entity_id'] || 'light.glitch_cube'

    if params['state'] == 'off'
      call_ha_service('light', 'turn_off', { entity_id: entity_id })
    else
      # Turn on with optional parameters
      service_data = { entity_id: entity_id }
      service_data[:brightness] = params['brightness'] if params['brightness']
      service_data[:rgb_color] = params['rgb_color'] if params['rgb_color']
      service_data[:transition] = params['transition'] || 2

      call_ha_service('light', 'turn_on', service_data)
    end
  end

  def self.speak_message(params)
    message = params['message'] || 'Hello from Glitch Cube!'
    entity_id = params['entity_id'] || 'media_player.square_voice'

    # Use TTS service through HA
    result = call_ha_service('tts', 'speak', {
      entity_id: entity_id,
      message: message
    })

    result.include?('✅') ? "Speaking: \"#{message}\"" : 'Failed to speak message'
  end

  def self.run_ha_script(params)
    script_name = params['script_name']
    return format_response(false, 'script_name required') unless script_name

    variables = params['variables'] || {}
    call_ha_script(script_name, variables)
  end
end
