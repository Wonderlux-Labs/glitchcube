# frozen_string_literal: true

require_relative 'base_tool'
require_relative '../services/logger_service'

# Tool for controlling RGB lighting hardware on the Glitch Cube
# Provides simple, direct control of lights with known entity mappings
class LightingTool < BaseTool
  def self.name
    'lighting_control'
  end

  def self.description
    'Control cube RGB lighting with specific methods for each action. Targets: cube, cart, voice_ring, matrix, indicators, all. Colors: hex "#FF0000" or RGB [255,0,0]'
  end

  def self.category
    'hardware_control'
  end

  def self.tool_prompt
    "Control RGB lighting with set_light(), turn_off_light(), set_effect(). Targets: cube, cart, voice_ring, matrix, indicators, all."
  end

  # Set light color and brightness
  def self.set_light(target: 'all', color: nil, brightness: 150, transition: 1)
    entity_ids = get_entities(target)
    return format_response(false, "Unknown target: #{target}") if entity_ids.empty?

    service_data = {
      entity_id: entity_ids,
      brightness: brightness,
      transition: transition
    }

    # Add color if provided
    if color
      rgb = parse_color(color)
      service_data[:rgb_color] = rgb if rgb
    end

    result = call_ha_service('light', 'turn_on', service_data)
    result.include?('✅') ? format_response(true, "Set #{target} to #{color || 'current'} at #{brightness}") : result
  rescue StandardError => e
    format_response(false, "Failed to set #{target}: #{e.message}")
  end

  # Set a lighting scene/mood
  def self.set_scene(mood: 'default')
    scenes = {
      'party' => { color: [255, 0, 255], brightness: 255, targets: ['all'] },
      'chill' => { color: [0, 100, 255], brightness: 100, targets: ['ambient'] },
      'alert' => { color: [255, 0, 0], brightness: 255, targets: ['indicators', 'voice_ring'] },
      'sleep' => { color: [255, 100, 0], brightness: 30, targets: ['ambient'] },
      'work' => { color: [255, 255, 255], brightness: 200, targets: ['cube', 'cart'] }
    }

    scene = scenes[mood.downcase]
    return format_response(false, "Unknown mood: #{mood}. Try: #{scenes.keys.join(', ')}") unless scene

    scene[:targets].each do |target|
      entity_ids = get_entities(target)
      call_ha_service('light', 'turn_on', {
        entity_id: entity_ids,
        rgb_color: scene[:color],
        brightness: scene[:brightness],
        transition: 2
      })
    end

    format_response(true, "Set mood: #{mood}")
  rescue StandardError => e
    format_response(false, "Failed to set mood: #{e.message}")
  end

  # Pulse effect
  def self.pulse_light(target: 'voice_ring', color: '#00FF00', pulses: 3)
    entity_ids = get_entities(target)
    return format_response(false, "Unknown target: #{target}") if entity_ids.empty?

    rgb = parse_color(color) || [0, 255, 0]

    # Simple pulse using HA script
    result = call_ha_script('cube_pulse_effect', {
      entity_id: entity_ids.first,
      color: rgb,
      pulses: pulses
    })

    if result.include?('✅')
      format_response(true, "Pulsing #{target} #{pulses} times")
    else
      # Fallback to manual pulse if script doesn't exist
      pulses.times do
        call_ha_service('light', 'turn_on', {
          entity_id: entity_ids,
          rgb_color: rgb,
          brightness: 255,
          transition: 0.5
        })
        sleep(0.5)
        call_ha_service('light', 'turn_on', {
          entity_id: entity_ids,
          brightness: 30,
          transition: 0.5
        })
        sleep(0.5)
      end
      format_response(true, "Pulsed #{target} #{pulses} times")
    end
  end

  # Turn off lights
  def self.turn_off(target: 'all', transition: 1)
    entity_ids = get_entities(target)
    return format_response(false, "Unknown target: #{target}") if entity_ids.empty?

    result = call_ha_service('light', 'turn_off', {
      entity_id: entity_ids,
      transition: transition
    })

    result.include?('✅') ? format_response(true, "Turned off #{target}") : result
  rescue StandardError => e
    format_response(false, "Failed to turn off #{target}: #{e.message}")
  end

  private

  # Known entity mappings for our hardware
  LIGHTS = {
    'cube' => 'light.cube_light',
    'cart' => 'light.cart_light',
    'voice_ring' => 'light.cube_voice_ring',
    'matrix' => 'light.awtrix_b85e20_matrix',
    'indicator_1' => 'light.awtrix_b85e20_indicator_1',
    'indicator_2' => 'light.awtrix_b85e20_indicator_2',
    'indicator_3' => 'light.awtrix_b85e20_indicator_3'
  }.freeze

  GROUPS = {
    'all' => LIGHTS.values,
    'ambient' => ['light.cube_light', 'light.cart_light'],
    'indicators' => ['light.awtrix_b85e20_indicator_1', 'light.awtrix_b85e20_indicator_2', 'light.awtrix_b85e20_indicator_3']
  }.freeze


  # Helper to get entity IDs from target name
  def self.get_entities(target)
    return GROUPS[target] if GROUPS.key?(target)
    return [LIGHTS[target]] if LIGHTS.key?(target)
    return [target] if target.start_with?('light.')
    []
  end

  # Parse color from various formats
  def self.parse_color(color)
    case color
    when String
      if color.start_with?('#')
        hex = color.gsub('#', '')
        return nil unless hex.match?(/^[0-9A-Fa-f]{6}$/)
        [
          hex[0..1].to_i(16),
          hex[2..3].to_i(16),
          hex[4..5].to_i(16)
        ]
      end
    when Array
      color if color.length == 3 && color.all? { |c| c.between?(0, 255) }
    end
  end
end