# frozen_string_literal: true

require_relative '../home_assistant_client'
require_relative '../services/logger_service'

# Tool for controlling RGB lighting hardware on the Glitch Cube
# Provides simple, direct control of lights with known entity mappings
class LightingTool
  def self.name
    'lighting_control'
  end

  def self.description
    'Control cube RGB lighting. Actions: "set" (target, color, brightness), "scene" (mood), "pulse" (target, color), "off" (target). Targets: cube, cart, voice_ring, matrix, indicators, all. Colors: hex "#FF0000" or RGB [255,0,0]. Args: action (string), params (string) - JSON parameters'
  end

  def self.call(action:, params: '{}')
    params = JSON.parse(params) if params.is_a?(String)
    client = HomeAssistantClient.new

    case action
    when 'set'
      set_light(client, params)
    when 'scene'
      set_scene(client, params)
    when 'pulse'
      pulse_light(client, params)
    when 'off'
      turn_off(client, params)
    else
      "Unknown action: #{action}. Available: set, scene, pulse, off"
    end
  rescue StandardError => e
    "Lighting error: #{e.message}"
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

  # Simple set light method
  def self.set_light(client, params)
    target = params['target'] || 'all'
    color = params['color']
    brightness = params['brightness'] || 150
    transition = params['transition'] || 1

    entity_ids = get_entities(target)
    return "Unknown target: #{target}" if entity_ids.empty?

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

    client.call_service('light', 'turn_on', service_data)
    "Set #{target} to #{color || 'current'} at #{brightness}"
  rescue StandardError => e
    "Failed to set #{target}: #{e.message}"
  end

  # Set a lighting scene/mood
  def self.set_scene(client, params)
    mood = params['mood'] || 'default'
    
    scenes = {
      'party' => { color: [255, 0, 255], brightness: 255, targets: ['all'] },
      'chill' => { color: [0, 100, 255], brightness: 100, targets: ['ambient'] },
      'alert' => { color: [255, 0, 0], brightness: 255, targets: ['indicators', 'voice_ring'] },
      'sleep' => { color: [255, 100, 0], brightness: 30, targets: ['ambient'] },
      'work' => { color: [255, 255, 255], brightness: 200, targets: ['cube', 'cart'] }
    }

    scene = scenes[mood.downcase]
    return "Unknown mood: #{mood}. Try: #{scenes.keys.join(', ')}" unless scene

    scene[:targets].each do |target|
      entity_ids = get_entities(target)
      client.call_service('light', 'turn_on', {
        entity_id: entity_ids,
        rgb_color: scene[:color],
        brightness: scene[:brightness],
        transition: 2
      })
    end

    "Set mood: #{mood}"
  rescue StandardError => e
    "Failed to set mood: #{e.message}"
  end

  # Pulse effect
  def self.pulse_light(client, params)
    target = params['target'] || 'voice_ring'
    color = params['color'] || '#00FF00'
    pulses = params['pulses'] || 3

    entity_ids = get_entities(target)
    return "Unknown target: #{target}" if entity_ids.empty?

    rgb = parse_color(color) || [0, 255, 0]

    # Simple pulse using HA script
    client.call_service('script', 'cube_pulse_effect', {
      entity_id: entity_ids.first,
      color: rgb,
      pulses: pulses
    })

    "Pulsing #{target} #{pulses} times"
  rescue StandardError => e
    # Fallback to manual pulse if script doesn't exist
    pulses.times do
      client.call_service('light', 'turn_on', {
        entity_id: entity_ids,
        rgb_color: rgb,
        brightness: 255,
        transition: 0.5
      })
      sleep(0.5)
      client.call_service('light', 'turn_on', {
        entity_id: entity_ids,
        brightness: 30,
        transition: 0.5
      })
      sleep(0.5)
    end
    "Pulsed #{target} #{pulses} times"
  end

  # Turn off lights
  def self.turn_off(client, params)
    target = params['target'] || 'all'
    entity_ids = get_entities(target)
    return "Unknown target: #{target}" if entity_ids.empty?

    client.call_service('light', 'turn_off', {
      entity_id: entity_ids,
      transition: params['transition'] || 1
    })

    "Turned off #{target}"
  rescue StandardError => e
    "Failed to turn off #{target}: #{e.message}"
  end

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