# frozen_string_literal: true

require_relative '../home_assistant_client'
require_relative '../services/logger_service'

# Tool for controlling all RGB lighting hardware
# Provides organized access to cube lighting, voice feedback, AWTRIX display lighting, and status indicators
class LightingTool
  def self.name
    'lighting_control'
  end

  def self.description
    'Control RGB lighting throughout the cube installation. Actions: "list_lights" (verbose: true/false - shows available lights and capabilities), "set_color" (light, color, brightness), "set_brightness" (light, brightness), "turn_off" (light), "mood_lighting" (group, color, brightness), "breathing_effect" (light, color, cycles), "get_status" (light). Use list_lights first to see available lights and groups. Colors: hex like "#FF0000" or RGB arrays. Args: action (string), params (string) - JSON with light, color, brightness, verbose, etc.'
  end

  def self.call(action:, params: '{}')
    params = JSON.parse(params) if params.is_a?(String)
    
    # Entity mapping - all RGB-capable lights based on our hardware scan
    lights = {
      # Primary ambient lighting
      'cube' => 'light.cube_light',                           # Main cube lighting (rgb + color_temp)
      'cart' => 'light.cart_light',                          # Cart/secondary lighting (rgb + color_temp)
      
      # Conversation feedback
      'voice_ring' => 'light.home_assistant_voice_09739d_led_ring', # Voice assistant LED ring
      
      # AWTRIX display system  
      'matrix' => 'light.awtrix_b85e20_matrix',               # Main 32x8 RGB matrix
      'indicator_1' => 'light.awtrix_b85e20_indicator_1',     # Status indicator 1
      'indicator_2' => 'light.awtrix_b85e20_indicator_2',     # Status indicator 2  
      'indicator_3' => 'light.awtrix_b85e20_indicator_3'      # Status indicator 3
    }

    # Light groups for coordinated effects
    groups = {
      'all' => lights.values,
      'primary' => [lights['cube'], lights['cart']],
      'ambient' => [lights['cube'], lights['cart'], lights['matrix']],
      'indicators' => [lights['indicator_1'], lights['indicator_2'], lights['indicator_3']],
      'awtrix' => [lights['matrix'], lights['indicator_1'], lights['indicator_2'], lights['indicator_3']],
      'conversation' => [lights['voice_ring'], lights['matrix']]
    }

    client = HomeAssistantClient.new

    case action
    when 'list_lights'
      list_available_lights(client, lights, groups, params)
    when 'set_color'
      set_light_color(client, lights, params)
    when 'set_brightness'
      set_light_brightness(client, lights, params)
    when 'turn_off'
      turn_off_light(client, lights, params)
    when 'mood_lighting'
      set_mood_lighting(client, groups, params)
    when 'breathing_effect'
      breathing_effect(client, lights, params)
    when 'get_status'
      get_light_status(client, lights, params)
    else
      "Unknown action: #{action}. Available actions: list_lights, set_color, set_brightness, turn_off, mood_lighting, breathing_effect, get_status"
    end
  rescue StandardError => e
    "Lighting control error: #{e.message}"
  end

  private

  # List all available lights with their current status and capabilities
  def self.list_available_lights(client, lights, groups, params)
    verbose = params['verbose'] != false # Default to verbose unless explicitly false
    
    result = []
    
    # Show available individual lights
    result << "=== AVAILABLE LIGHTS ==="
    
    if verbose
      lights.each do |key, entity_id|
        begin
          state = client.state(entity_id)
          
          if state && state['state'] != 'unavailable'
            # Get detailed info about the light's capabilities
            supported_modes = state.dig('attributes', 'supported_color_modes') || []
            current_brightness = state.dig('attributes', 'brightness')
            current_rgb = state.dig('attributes', 'rgb_color')
            friendly_name = state.dig('attributes', 'friendly_name')
            
            light_info = "#{key} (#{entity_id}): #{state['state']}"
            light_info += " - #{friendly_name}" if friendly_name != entity_id
            light_info += " | Modes: #{supported_modes.join(', ')}" if supported_modes.any?
            light_info += " | Brightness: #{current_brightness}" if current_brightness
            light_info += " | Color: #{current_rgb}" if current_rgb
            
            result << "  ✅ #{light_info}"
          else
            result << "  ❌ #{key} (#{entity_id}): unavailable"
          end
        rescue => e
          result << "  ❌ #{key} (#{entity_id}): error - #{e.message}"
        end
      end
      
      # Show available groups in verbose mode
      result << ""
      result << "=== AVAILABLE GROUPS ==="
      groups.each do |group_name, entity_list|
        available_count = 0
        entity_list.each do |entity_id|
          begin
            state = client.state(entity_id)
            available_count += 1 if state && state['state'] != 'unavailable'
          rescue
            # Skip unavailable lights
          end
        end
        
        result << "  #{group_name}: #{available_count}/#{entity_list.size} lights available"
        if available_count < entity_list.size
          result << "    (some lights offline or unavailable)"
        end
      end
      
      # Usage examples
      result << ""
      result << "=== USAGE EXAMPLES ==="
      result << 'Set cube to red: {"action": "set_color", "params": {"light": "cube", "color": "#FF0000", "brightness": 200}}'
      result << 'Mood lighting: {"action": "mood_lighting", "params": {"group": "ambient", "color": "#00FF80", "brightness": 150}}'
      result << 'Breathing effect: {"action": "breathing_effect", "params": {"light": "voice_ring", "color": "#FF00FF", "cycles": 3}}'
      
    else
      # Simple list
      available_lights = []
      lights.each do |key, entity_id|
        begin
          state = client.state(entity_id)
          available_lights << key if state && state['state'] != 'unavailable'
        rescue
          # Skip errors in simple mode
        end
      end
      
      result << "Available: #{available_lights.join(', ')}"
      result << "Groups: #{groups.keys.join(', ')}"
      result << 'Use verbose: true for detailed capabilities'
    end
    
    Services::LoggerService.log_api_call(
      service: 'lighting_tool',
      endpoint: 'list_lights',
      verbose: verbose,
      available_count: lights.size
    )
    
    result.join("\n")
  rescue => e
    "Error listing lights: #{e.message}"
  end

  # Set color and optionally brightness for a specific light
  def self.set_light_color(client, lights, params)
    light_key = params['light']
    color = params['color']
    brightness = params['brightness']
    transition = params['transition'] || 1

    return 'Error: light and color required' unless light_key && color

    entity_id = lights[light_key.to_s]
    return "Error: Unknown light '#{light_key}'. Available: #{lights.keys.join(', ')}" unless entity_id

    rgb_color = parse_color(color)
    return "Error: Invalid color format. Use hex like '#FF0000' or RGB array [255,0,0]" unless rgb_color

    service_data = { entity_id: entity_id, rgb_color: rgb_color, transition: transition }
    service_data[:brightness] = brightness if brightness

    begin
      response = client.call_service('light', 'turn_on', service_data)
      color_desc = color.is_a?(String) ? color : rgb_color.to_s
      brightness_desc = brightness ? " at #{brightness} brightness" : ""
      
      Services::LoggerService.log_api_call(
        service: 'lighting_tool',
        endpoint: 'set_color',
        entity_id: entity_id,
        color: color_desc,
        brightness: brightness
      )

      "Set #{light_key} to #{color_desc}#{brightness_desc}"
    rescue => e
      "Failed to set #{light_key} color: #{e.message}"
    end
  end

  # Set brightness only (preserve current color)
  def self.set_light_brightness(client, lights, params)
    light_key = params['light']
    brightness = params['brightness']

    return 'Error: light and brightness required' unless light_key && brightness

    entity_id = lights[light_key.to_s]
    return "Error: Unknown light '#{light_key}'. Available: #{lights.keys.join(', ')}" unless entity_id

    begin
      response = client.call_service('light', 'turn_on', { 
        entity_id: entity_id, 
        brightness: brightness,
        transition: params['transition'] || 1
      })

      Services::LoggerService.log_api_call(
        service: 'lighting_tool',
        endpoint: 'set_brightness',
        entity_id: entity_id,
        brightness: brightness
      )

      "Set #{light_key} brightness to #{brightness}"
    rescue => e
      "Failed to set #{light_key} brightness: #{e.message}"
    end
  end

  # Turn off a light
  def self.turn_off_light(client, lights, params)
    light_key = params['light']
    return 'Error: light required' unless light_key

    entity_id = lights[light_key.to_s]
    return "Error: Unknown light '#{light_key}'. Available: #{lights.keys.join(', ')}" unless entity_id

    begin
      response = client.call_service('light', 'turn_off', { entity_id: entity_id })
      "Turned off #{light_key}"
    rescue => e
      "Failed to turn off #{light_key}: #{e.message}"
    end
  end

  # Set coordinated mood lighting across multiple lights
  def self.set_mood_lighting(client, groups, params)
    group_key = params['group'] || 'primary'
    color = params['color']
    brightness = params['brightness'] || 150

    return 'Error: color required' unless color

    entity_ids = groups[group_key.to_s]
    return "Error: Unknown group '#{group_key}'. Available: #{groups.keys.join(', ')}" unless entity_ids

    rgb_color = parse_color(color)
    return "Error: Invalid color format. Use hex like '#FF0000' or RGB array [255,0,0]" unless rgb_color

    begin
      # Set all lights in group simultaneously
      response = client.call_service('light', 'turn_on', {
        entity_id: entity_ids,
        rgb_color: rgb_color,
        brightness: brightness,
        transition: params['transition'] || 2
      })

      color_desc = color.is_a?(String) ? color : rgb_color.to_s

      Services::LoggerService.log_api_call(
        service: 'lighting_tool',
        endpoint: 'mood_lighting',
        group: group_key,
        entity_count: entity_ids.size,
        color: color_desc,
        brightness: brightness
      )

      "Set #{group_key} group (#{entity_ids.size} lights) to #{color_desc} mood lighting"
    rescue => e
      "Failed to set #{group_key} mood lighting: #{e.message}"
    end
  end

  # Breathing effect - fade in/out cycles
  def self.breathing_effect(client, lights, params)
    light_key = params['light']
    color = params['color']
    cycles = params['cycles'] || 3
    duration = params['duration'] || 3

    return 'Error: light and color required' unless light_key && color

    entity_id = lights[light_key.to_s]
    return "Error: Unknown light '#{light_key}'. Available: #{lights.keys.join(', ')}" unless entity_id

    rgb_color = parse_color(color)
    return "Error: Invalid color format" unless rgb_color

    begin
      cycles.times do |cycle|
        # Fade in
        client.call_service('light', 'turn_on', {
          entity_id: entity_id,
          rgb_color: rgb_color,
          brightness: 255,
          transition: duration / 2
        })
        
        sleep(duration / 2)
        
        # Fade out
        client.call_service('light', 'turn_on', {
          entity_id: entity_id,
          brightness: 30,
          transition: duration / 2
        })
        
        sleep(duration / 2)
      end

      color_desc = color.is_a?(String) ? color : rgb_color.to_s
      
      Services::LoggerService.log_api_call(
        service: 'lighting_tool',
        endpoint: 'breathing_effect',
        entity_id: entity_id,
        cycles: cycles,
        color: color_desc
      )

      "Completed #{cycles} breathing cycles on #{light_key}"
    rescue => e
      "Failed breathing effect on #{light_key}: #{e.message}"
    end
  end

  # Get current status of a light
  def self.get_light_status(client, lights, params)
    light_key = params['light']
    
    if light_key
      # Get status of specific light
      entity_id = lights[light_key.to_s]
      return "Error: Unknown light '#{light_key}'. Available: #{lights.keys.join(', ')}" unless entity_id

      begin
        state = client.state(entity_id)
        format_light_status(light_key, state)
      rescue => e
        "Error getting #{light_key} status: #{e.message}"
      end
    else
      # Get status of all lights
      statuses = []
      lights.each do |key, entity_id|
        begin
          state = client.state(entity_id)
          statuses << format_light_status(key, state)
        rescue => e
          statuses << "#{key}: Error - #{e.message}"
        end
      end
      statuses.join(', ')
    end
  end

  # Parse color from hex string or RGB array
  def self.parse_color(color)
    case color
    when String
      # Hex color like '#FF0000' or 'FF0000'
      hex = color.gsub('#', '')
      return nil unless hex.match?(/^[0-9A-Fa-f]{6}$/)
      
      [
        hex[0..1].to_i(16),  # Red
        hex[2..3].to_i(16),  # Green  
        hex[4..5].to_i(16)   # Blue
      ]
    when Array
      # RGB array like [255, 0, 0]
      return color if color.length == 3 && color.all? { |c| c.is_a?(Integer) && c.between?(0, 255) }
    end
    
    nil
  end

  # Format light state for readable output
  def self.format_light_status(light_key, state)
    return "#{light_key}: unavailable" unless state && state['state'] != 'unavailable'

    status_parts = ["#{light_key}: #{state['state']}"]
    
    if state['state'] == 'on'
      brightness = state.dig('attributes', 'brightness')
      rgb_color = state.dig('attributes', 'rgb_color')
      
      status_parts << "brightness #{brightness}" if brightness
      status_parts << "rgb #{rgb_color}" if rgb_color
    end

    status_parts.join(', ')
  end
end