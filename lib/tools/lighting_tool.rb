#  frozen_string_literal: true

module Tools
  # Tool for controlling RGB lighting hardware on the Glitch Cube
  # Provides simple, direct control of lights with known entity mappings
  class LightingTool < BaseTool
    def self.name
      'lighting_control'
    end

    def self.description
      'Control physical RGB LED lights on Glitch Cube hardware. Main lights: cube (main LED strips), cart (mobile unit LEDs), awtrix_mood_light (32x8 LED matrix ambient). Colors: hex "#FF0000" or RGB [255,0,0]'
    end

    def self.category
      'hardware_control'
    end

    def self.tool_prompt
      'Control RGB lighting with set_state(), get_state(), list_states(), list_effects(entity_id), set_effect(entity_id, effect). Main targets: cube (LED strips), cart (mobile LEDs), matrix (LED matrix). Use list_effects first to see available effects per light.'
    end

    # List of available tool methods for this class
    def self.available_tools
      %w[set_state get_state list_states list_effects set_effect]
    end

    # Prompt description for LLM
    def self.prompt_description
      'Control RGB lighting on cube hardware - set colors, brightness, effects'
    end

    # Tool schemas for each method
    def self.tool_schemas
      {
        'set_state' => {
          'type' => 'object',
          'properties' => {
            'state' => { 'type' => 'string', 'enum' => %w[on off] },
            'target' => { 'type' => 'string', 'enum' => %w[cube cart voice_ring matrix indicators all] },
            'color' => { 'type' => 'string' },
            'brightness' => { 'type' => 'integer', 'minimum' => 0, 'maximum' => 255 }
          },
          'required' => ['state']
        },
        'get_state' => {
          'type' => 'object',
          'properties' => {
            'target' => { 'type' => 'string', 'enum' => %w[cube cart voice_ring matrix indicators all] }
          }
        },
        'list_states' => { 'type' => 'object', 'properties' => {} },
        'list_effects' => {
          'type' => 'object',
          'properties' => {
            'entity_id' => { 'type' => 'string' }
          },
          'required' => ['entity_id']
        },
        'set_effect' => {
          'type' => 'object',
          'properties' => {
            'entity_id' => { 'type' => 'string' },
            'effect' => { 'type' => 'string' }
          },
          'required' => %w[entity_id effect]
        }
      }
    end

    # Main method for setting light state
    def self.set_state(state:, target: 'all', color: nil, brightness: 150, **_kwargs)
      return turn_off(target: target) if state == 'off'

      set_light(target: target, color: color, brightness: brightness)
    end

    # Get current state of lights
    def self.get_state(target: 'all', **_kwargs)
      entity_ids = get_entities(target)
      states = {}

      entity_ids.each do |entity_id|
        state = get_ha_state(entity_id)
        states[entity_id] = state
      end

      format_response(true, 'Light states retrieved', states)
    end

    # List all light states
    def self.list_states(**_kwargs)
      all_targets = %w[cube cart voice_ring matrix indicators]
      states = {}

      all_targets.each do |target|
        entity_ids = get_entities(target)
        entity_ids.each do |entity_id|
          state = get_ha_state(entity_id)
          states[target] = state
        end
      end

      format_response(true, 'All light states', states)
    end

    # List available effects for a specific light entity
    def self.list_effects(entity_id:, **_kwargs)
      # Convert target names to entity IDs if needed
      entity_id = convert_target_to_entity_id(entity_id)

      state = get_ha_state(entity_id)
      return format_response(false, state) if state.is_a?(String) # Error message from get_ha_state

      effect_list = state[:attributes][:effect_list]
      return format_response(false, "No effects available for #{entity_id}") unless effect_list

      format_response(true, "Available effects for #{entity_id}", { entity_id: entity_id, effects: effect_list })
    rescue StandardError => e
      format_response(false, "Failed to get effects for #{entity_id}: #{e.message}")
    end

    # Set effect for a specific light entity
    def self.set_effect(entity_id:, effect:, **_kwargs)
      # Convert target names to entity IDs if needed
      entity_id = convert_target_to_entity_id(entity_id)

      # Validate the entity exists and supports effects
      state = get_ha_state(entity_id)
      return format_response(false, state) if state.is_a?(String) # Error message from get_ha_state

      effect_list = state[:attributes][:effect_list]
      return format_response(false, "#{entity_id} does not support effects") unless effect_list
      return format_response(false, "Effect '#{effect}' not available for #{entity_id}. Available: #{effect_list.join(', ')}") unless effect_list.include?(effect)

      service_data = {
        entity_id: entity_id,
        effect: effect
      }

      result = call_ha_service('light', 'turn_on', service_data)
      result.include?('✅') ? format_response(true, "Set #{entity_id} effect to #{effect}") : result
    rescue StandardError => e
      format_response(false, "Failed to set effect for #{entity_id}: #{e.message}")
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
        'alert' => { color: [255, 0, 0], brightness: 255, targets: %w[indicators voice_ring] },
        'sleep' => { color: [255, 100, 0], brightness: 30, targets: ['ambient'] },
        'work' => { color: [255, 255, 255], brightness: 200, targets: %w[cube cart] }
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

    # Known entity mappings for our hardware - simplified to actual used lights
    LIGHTS = {
      'cube' => 'light.cube_light',  # Main Govee LED strips on cube structure
      'cart' => 'light.cart_light',  # LED strips on mobile cart
      'awtrix_mood_light' => 'light.awtrix_b85e20_matrix',  # Awtrix 32x8 LED matrix ambient lighting
      'matrix' => 'light.awtrix_b85e20_matrix',  # Alias for backward compatibility
      'voice_ring' => 'light.cube_voice_ring',  # Voice indicator ring (rarely used)
      'indicator_1' => 'light.awtrix_b85e20_indicator_1',
      'indicator_2' => 'light.awtrix_b85e20_indicator_2',
      'indicator_3' => 'light.awtrix_b85e20_indicator_3'
    }.freeze

    GROUPS = {
      'all' => LIGHTS.values,
      'ambient' => ['light.cube_light', 'light.cart_light', 'light.awtrix_b85e20_matrix'],  # Main ambient lighting
      'indicators' => ['light.awtrix_b85e20_indicator_1', 'light.awtrix_b85e20_indicator_2', 'light.awtrix_b85e20_indicator_3']
    }.freeze

    # Helper to get entity IDs from target name
    def self.get_entities(target)
      return GROUPS[target] if GROUPS.key?(target)
      return [LIGHTS[target]] if LIGHTS.key?(target)
      return [target] if target.start_with?('light.')

      []
    end

    # Helper to convert target names to single entity IDs (for effects)
    def self.convert_target_to_entity_id(target)
      return LIGHTS[target] if LIGHTS.key?(target)
      return target if target.start_with?('light.')

      # If it's a group, return the first entity (effects are per-entity)
      if GROUPS.key?(target)
        return GROUPS[target].first
      end

      # Smart lookup - check if any light entity contains the target name
      matching_entity = LIGHTS.values.find { |entity_id| entity_id.include?(target) }
      return matching_entity if matching_entity

      target # Return as-is if no conversion found
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
end
