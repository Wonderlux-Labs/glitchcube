# frozen_string_literal: true

require_relative '../home_assistant_client'
require_relative 'circuit_breaker_service'
require_relative 'logger_service'

module Services
  class LightingService
    # All available RGB-capable light entities
    # Updated based on entity scan from EXISTING_SERVICES_AND_HARDWARE.md
    LIGHT_ENTITIES = {
      # Primary cube lighting - main ambient mood lighting
      cube: 'light.cube_light',
      
      # Secondary/cart lighting - environmental/area mood lighting  
      cart: 'light.cart_light',
      
      # Voice assistant LED ring - conversation feedback, mood indication
      voice_ring: 'light.home_assistant_voice_09739d_led_ring',
      
      # AWTRIX LED matrix display - text display + background mood lighting
      matrix: 'light.awtrix_b85e20_matrix',
      
      # AWTRIX status indicators - multi-color status indication, breathing effects
      indicator_1: 'light.awtrix_b85e20_indicator_1',
      indicator_2: 'light.awtrix_b85e20_indicator_2',
      indicator_3: 'light.awtrix_b85e20_indicator_3'
    }.freeze

    # Light groups for coordinated effects
    LIGHT_GROUPS = {
      all: LIGHT_ENTITIES.values,
      primary: %w[light.cube_light light.cart_light],
      ambient: %w[light.cube_light light.cart_light light.awtrix_b85e20_matrix],
      indicators: %w[light.awtrix_b85e20_indicator_1 light.awtrix_b85e20_indicator_2 light.awtrix_b85e20_indicator_3],
      awtrix: %w[light.awtrix_b85e20_matrix light.awtrix_b85e20_indicator_1 light.awtrix_b85e20_indicator_2 light.awtrix_b85e20_indicator_3],
      conversation: %w[light.home_assistant_voice_09739d_led_ring light.awtrix_b85e20_matrix]
    }.freeze

    class << self
      # Quick access methods for common operations
      def set_mood_lighting(color, brightness: 150, entities: :primary)
        new.change_color_multiple(entities, color: color, brightness: brightness)
      end

      def conversation_feedback(color, brightness: 200)
        new.change_color_multiple(:conversation, color: color, brightness: brightness)
      end

      def turn_off_all
        new.turn_off_multiple(:all)
      end
    end

    def initialize
      @home_assistant = HomeAssistantClient.new
      @logger = Services::LoggerService
    end

    # Change color of a single light
    def change_color(light_key, color:, brightness: nil, transition: nil)
      entity_id = resolve_entity_id(light_key)
      return false unless entity_id

      data = build_light_data(entity_id, color: color, brightness: brightness, transition: transition)
      
      execute_with_logging("change_color", entity_id) do
        @home_assistant.call_service('light', 'turn_on', data)
      end
    end

    # Change color of multiple lights (supports groups or arrays)
    def change_color_multiple(lights, color:, brightness: nil, transition: nil)
      entity_ids = resolve_multiple_entity_ids(lights)
      return false if entity_ids.empty?

      data = build_light_data(entity_ids, color: color, brightness: brightness, transition: transition)
      
      execute_with_logging("change_color_multiple", entity_ids.join(', ')) do
        @home_assistant.call_service('light', 'turn_on', data)
      end
    end

    # Set brightness only (preserve current color)
    def set_brightness(light_key, brightness)
      entity_id = resolve_entity_id(light_key)
      return false unless entity_id

      data = { entity_id: entity_id, brightness: brightness }
      
      execute_with_logging("set_brightness", entity_id) do
        @home_assistant.call_service('light', 'turn_on', data)
      end
    end

    # Turn on light with optional color/brightness
    def turn_on(light_key, color: nil, brightness: nil)
      entity_id = resolve_entity_id(light_key)
      return false unless entity_id

      data = { entity_id: entity_id }
      data[:rgb_color] = parse_color(color) if color
      data[:brightness] = brightness if brightness
      
      execute_with_logging("turn_on", entity_id) do
        @home_assistant.call_service('light', 'turn_on', data)
      end
    end

    # Turn off single light
    def turn_off(light_key)
      entity_id = resolve_entity_id(light_key)
      return false unless entity_id

      execute_with_logging("turn_off", entity_id) do
        @home_assistant.call_service('light', 'turn_off', { entity_id: entity_id })
      end
    end

    # Turn off multiple lights
    def turn_off_multiple(lights)
      entity_ids = resolve_multiple_entity_ids(lights)
      return false if entity_ids.empty?

      execute_with_logging("turn_off_multiple", entity_ids.join(', ')) do
        @home_assistant.call_service('light', 'turn_off', { entity_id: entity_ids })
      end
    end

    # Get current state of a light
    def get_light_state(light_key)
      entity_id = resolve_entity_id(light_key)
      return nil unless entity_id

      begin
        state = @home_assistant.state(entity_id)
        parse_light_state(state)
      rescue HomeAssistantClient::Error => e
        @logger.log_api_call(
          service: 'lighting_service',
          endpoint: 'get_state_error',
          entity_id: entity_id,
          error: e.message
        )
        nil
      end
    end

    # Check if light is available/responsive
    def light_available?(light_key)
      state = get_light_state(light_key)
      state && state[:state] != 'unavailable'
    end

    # Get all available lights with their current states
    def get_all_light_states
      states = {}
      LIGHT_ENTITIES.each do |key, entity_id|
        states[key] = get_light_state(key)
      end
      states.compact
    end

    # Breathing effect for a light (fade in/out)
    def breathing_effect(light_key, color:, duration: 3, cycles: 3)
      entity_id = resolve_entity_id(light_key)
      return false unless entity_id

      execute_with_logging("breathing_effect", entity_id) do
        cycles.times do
          # Fade in
          change_color(light_key, color: color, brightness: 255, transition: duration / 2)
          sleep(duration / 2)
          
          # Fade out  
          set_brightness(light_key, 50)
          sleep(duration / 2)
        end
      end
    end

    private

    # Resolve light key to entity ID
    def resolve_entity_id(light_key)
      case light_key
      when Symbol
        LIGHT_ENTITIES[light_key]
      when String
        # Allow direct entity IDs or string keys
        light_key.start_with?('light.') ? light_key : LIGHT_ENTITIES[light_key.to_sym]
      else
        nil
      end
    end

    # Resolve multiple lights (groups, arrays, etc.)
    def resolve_multiple_entity_ids(lights)
      case lights
      when Symbol
        # Group name
        LIGHT_GROUPS[lights] || []
      when Array
        # Array of light keys
        lights.map { |light| resolve_entity_id(light) }.compact
      when String
        # Single light as string
        [resolve_entity_id(lights)].compact
      else
        []
      end
    end

    # Build Home Assistant light service data
    def build_light_data(entity_ids, color: nil, brightness: nil, transition: nil)
      data = { entity_id: Array(entity_ids) }
      
      if color
        rgb_color = parse_color(color)
        data[:rgb_color] = rgb_color if rgb_color
      end
      
      data[:brightness] = brightness if brightness
      data[:transition] = transition if transition
      
      data
    end

    # Parse color from various formats (hex, rgb array, etc.)
    def parse_color(color)
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

    # Parse Home Assistant light state response
    def parse_light_state(ha_state)
      return nil unless ha_state

      {
        state: ha_state['state'],
        brightness: ha_state.dig('attributes', 'brightness'),
        rgb_color: ha_state.dig('attributes', 'rgb_color'),
        color_mode: ha_state.dig('attributes', 'color_mode'),
        supported_color_modes: ha_state.dig('attributes', 'supported_color_modes'),
        friendly_name: ha_state.dig('attributes', 'friendly_name')
      }
    end

    # Execute Home Assistant call with error handling and logging
    def execute_with_logging(operation, entity_info, &block)
      start_time = Time.now
      
      begin
        result = block.call
        
        duration = ((Time.now - start_time) * 1000).round
        @logger.log_api_call(
          service: 'lighting_service',
          endpoint: operation,
          entity_id: entity_info,
          duration: duration,
          success: true
        )
        
        result
      rescue HomeAssistantClient::Error => e
        duration = ((Time.now - start_time) * 1000).round
        @logger.log_api_call(
          service: 'lighting_service',
          endpoint: operation,
          entity_id: entity_info,
          duration: duration,
          error: e.message
        )
        
        puts "⚠️  Lighting operation failed: #{operation} on #{entity_info} - #{e.message}"
        false
      end
    end
  end
end