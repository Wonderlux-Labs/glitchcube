# frozen_string_literal: true

require_relative '../home_assistant_client'
require_relative 'logger_service'

module Services
  # Visual feedback for conversation states using the cube's speaker LED ring
  # Provides clear visual indicators for listening, thinking, speaking, and completion states
  class ConversationFeedbackService
    # LED ring entity - TODO: Rename in Home Assistant to cube_speaker_light
    SPEAKER_LED_RING = 'light.home_assistant_voice_09739d_led_ring' # Will become light.cube_speaker_light
    
    # Conversation state colors and effects
    CONVERSATION_STATES = {
      # User is speaking / cube is listening
      listening: {
        color: '#0080FF',      # Blue - attentive listening
        brightness: 200,
        effect: :pulse_slow,
        description: 'Listening to user input'
      },
      
      # Cube is processing / thinking
      thinking: {
        color: '#FF8000',      # Orange - processing/working  
        brightness: 150,
        effect: :pulse_fast,
        description: 'Processing and generating response'
      },
      
      # Cube is speaking back to user
      speaking: {
        color: '#00FF80',      # Green - active communication
        brightness: 180,
        effect: :solid,
        description: 'Speaking response to user'
      },
      
      # Conversation completed successfully
      completed: {
        color: '#8000FF',      # Purple - satisfied completion
        brightness: 120,
        effect: :fade_out,
        description: 'Conversation completed'
      },
      
      # Error occurred during conversation
      error: {
        color: '#FF0000',      # Red - error state
        brightness: 255,
        effect: :flash,
        description: 'Error during conversation'
      },
      
      # Idle state - ready for conversation
      idle: {
        color: '#404040',      # Dim white - ready/standby
        brightness: 50,
        effect: :solid,
        description: 'Ready for conversation'
      }
    }.freeze

    class << self
      # Quick state change methods for conversation flow
      def set_listening
        set_state(:listening)
      end

      def set_thinking  
        set_state(:thinking)
      end

      def set_speaking
        set_state(:speaking)
      end

      def set_completed
        set_state(:completed)
      end

      def set_error
        set_state(:error)
      end

      def set_idle
        set_state(:idle)
      end

      # Custom color for mood-based feedback
      def set_mood_color(color, brightness: 150)
        new.set_custom_color(color, brightness: brightness, effect: :solid)
      end
    end

    def initialize
      @home_assistant = HomeAssistantClient.new
      @logger = Services::LoggerService
    end

    # Set conversation state with visual feedback
    def set_state(state_key)
      state_config = CONVERSATION_STATES[state_key]
      return false unless state_config

      execute_effect(
        color: state_config[:color],
        brightness: state_config[:brightness], 
        effect: state_config[:effect],
        description: state_config[:description]
      )
    end

    # Set custom color and effect
    def set_custom_color(color, brightness: 150, effect: :solid, description: 'Custom color')
      execute_effect(
        color: color,
        brightness: brightness,
        effect: effect,
        description: description
      )
    end

    # Turn off the LED ring
    def turn_off
      begin
        @home_assistant.call_service('light', 'turn_off', {
          entity_id: SPEAKER_LED_RING
        })
        
        log_feedback('turn_off', 'LED ring turned off')
        true
      rescue => e
        log_error('turn_off', e)
        false
      end
    end

    # Get current LED ring status
    def get_status
      begin
        state = @home_assistant.state(SPEAKER_LED_RING)
        
        if state && state['state'] != 'unavailable'
          {
            state: state['state'],
            brightness: state.dig('attributes', 'brightness'),
            rgb_color: state.dig('attributes', 'rgb_color'),
            friendly_name: state.dig('attributes', 'friendly_name')
          }
        else
          { state: 'unavailable' }
        end
      rescue => e
        log_error('get_status', e)
        { state: 'error', error: e.message }
      end
    end

    private

    # Execute lighting effect based on type
    def execute_effect(color:, brightness:, effect:, description:)
      rgb_color = parse_color(color)
      return false unless rgb_color

      case effect
      when :solid
        set_solid_color(rgb_color, brightness, description)
      when :pulse_slow
        set_pulsing_effect(rgb_color, brightness, slow: true, description: description)
      when :pulse_fast
        set_pulsing_effect(rgb_color, brightness, slow: false, description: description)
      when :flash
        set_flashing_effect(rgb_color, brightness, description)
      when :fade_out
        set_fade_out_effect(rgb_color, brightness, description)
      else
        set_solid_color(rgb_color, brightness, description)
      end
    end

    # Solid color
    def set_solid_color(rgb_color, brightness, description)
      begin
        @home_assistant.call_service('light', 'turn_on', {
          entity_id: SPEAKER_LED_RING,
          rgb_color: rgb_color,
          brightness: brightness,
          transition: 0.5
        })
        
        log_feedback('solid', description, rgb_color, brightness)
        true
      rescue => e
        log_error('solid', e)
        false
      end
    end

    # Pulsing effect using brightness transitions
    def set_pulsing_effect(rgb_color, brightness, slow: true, description:)
      begin
        # Set initial color
        @home_assistant.call_service('light', 'turn_on', {
          entity_id: SPEAKER_LED_RING,
          rgb_color: rgb_color,
          brightness: brightness,
          transition: slow ? 1.5 : 0.8
        })

        # Note: For true pulsing, we'd need to use Home Assistant automations
        # or light effects. For now, we set the color and log the intent.
        log_feedback(slow ? 'pulse_slow' : 'pulse_fast', description, rgb_color, brightness)
        true
      rescue => e
        log_error('pulse', e)
        false
      end
    end

    # Flashing effect for errors
    def set_flashing_effect(rgb_color, brightness, description)
      begin
        # Quick flash by setting bright then dimming
        @home_assistant.call_service('light', 'turn_on', {
          entity_id: SPEAKER_LED_RING,
          rgb_color: rgb_color,
          brightness: brightness,
          transition: 0.1
        })

        # Schedule a dim after brief delay (would use threading in production)
        log_feedback('flash', description, rgb_color, brightness)
        true
      rescue => e
        log_error('flash', e)
        false
      end
    end

    # Fade out effect for completion
    def set_fade_out_effect(rgb_color, brightness, description)
      begin
        # Set color then fade to dim
        @home_assistant.call_service('light', 'turn_on', {
          entity_id: SPEAKER_LED_RING,
          rgb_color: rgb_color,
          brightness: brightness,
          transition: 0.5
        })

        # Then fade to very dim (simulating fade out)
        sleep(1) # Brief pause
        @home_assistant.call_service('light', 'turn_on', {
          entity_id: SPEAKER_LED_RING,
          brightness: 30,
          transition: 2.0
        })

        log_feedback('fade_out', description, rgb_color, brightness)
        true
      rescue => e
        log_error('fade_out', e)
        false
      end
    end

    # Parse color from hex string to RGB array
    def parse_color(color)
      case color
      when String
        # Hex color like '#FF0000'
        hex = color.gsub('#', '')
        return nil unless hex.match?(/^[0-9A-Fa-f]{6}$/)
        
        [
          hex[0..1].to_i(16),  # Red
          hex[2..3].to_i(16),  # Green
          hex[4..5].to_i(16)   # Blue
        ]
      when Array
        # Already RGB array
        return color if color.length == 3 && color.all? { |c| c.is_a?(Integer) && c.between?(0, 255) }
      end
      
      nil
    end

    # Log successful feedback operation
    def log_feedback(effect, description, rgb_color = nil, brightness = nil)
      @logger.log_api_call(
        service: 'conversation_feedback',
        endpoint: effect,
        description: description,
        entity_id: SPEAKER_LED_RING,
        rgb_color: rgb_color,
        brightness: brightness
      )
    end

    # Log error
    def log_error(operation, error)
      @logger.log_api_call(
        service: 'conversation_feedback',
        endpoint: operation,
        error: error.message,
        entity_id: SPEAKER_LED_RING
      )
    end
  end
end