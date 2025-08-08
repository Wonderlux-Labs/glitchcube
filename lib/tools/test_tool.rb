# frozen_string_literal: true

require_relative 'base_tool'

class TestTool < BaseTool
  def self.name
    'test_tool'
  end

  def self.description
    'Get system information. Args: info_type (string) - battery, location, sensors, or all'
  end

  def self.tool_prompt
    "Get system info with get_info(). Types: battery, location, sensors, all."
  end

  def self.parameters
    {
      'info_type' => {
        type: 'string',
        description: 'Type of information to retrieve',
        enum: %w[battery location sensors all]
      }
    }
  end

  def self.required_parameters
    []
  end

  def self.category
    'system_integration'
  end

  def self.call(info_type: 'all')
    result = perform_action(info_type)
    # Convert result to string for ReAct module
    format_result(result)
  end

  def self.format_result(result)
    if result[:error]
      format_response(false, result[:error])
    else
      formatted_result = result.map { |k, v| "#{k}: #{v.is_a?(Hash) ? v.to_json : v}" }.join(', ')
      format_response(true, formatted_result)
    end
  end

  def self.perform_action(info_type)
    case info_type
    when 'battery'
      {
        battery_level: '87%',
        charging: false,
        time_remaining: '21 hours',
        solar_panel_status: 'inactive (nighttime)'
      }
    when 'location'
      {
        current_location: 'Art Gallery Main Hall',
        gps_coordinates: '40.7128° N, 74.0060° W',
        elevation: '10 meters',
        last_moved: '2 hours ago'
      }
    when 'sensors'
      {
        temperature: '22°C',
        humidity: '45%',
        light_level: 'moderate',
        motion_detected: true,
        sound_level: '65 dB',
        proximity_sensors: {
          front: '2.3 meters',
          back: 'clear',
          left: '1.1 meters',
          right: '0.8 meters'
        }
      }
    when 'all'
      {
        battery: call(info_type: 'battery'),
        location: call(info_type: 'location'),
        sensors: call(info_type: 'sensors')
      }
    else
      { error: "Unknown info type: #{info_type}" }
    end
  end
end
