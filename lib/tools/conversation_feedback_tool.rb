# frozen_string_literal: true

require_relative 'base_tool'
require_relative '../services/conversation_feedback_service'
require_relative '../services/logger_service'

# Tool for controlling visual conversation feedback through LED ring
# Provides clear visual indicators for conversation states and moods
class ConversationFeedbackTool < BaseTool
  def self.name
    'conversation_feedback'
  end

  def self.description
    'Control LED ring feedback for conversation states. States: listening, thinking, speaking, completed, error, idle. Also supports custom colors and moods.'
  end

  def self.category
    'visual_interface'
  end

  def self.tool_prompt
    "Set conversation state with set_state(). Use custom colors with set_custom_color(). Control with turn_off(), get_status()."
  end

  # Set conversation state with predefined visual feedback
  def self.set_state(state:)
    valid_states = %w[listening thinking speaking completed error idle]
    
    unless valid_states.include?(state.to_s)
      return format_response(false, "Invalid state '#{state}'. Valid states: #{valid_states.join(', ')}")
    end

    begin
      feedback_service = Services::ConversationFeedbackService.new
      success = feedback_service.set_state(state.to_sym)
      
      Services::LoggerService.log_api_call(
        service: 'conversation_feedback_tool',
        endpoint: 'set_state',
        state: state,
        success: success
      )

      if success
        state_info = Services::ConversationFeedbackService::CONVERSATION_STATES[state.to_sym]
        description = state_info[:description] if state_info
        
        "Set conversation feedback to '#{state}' state" + (description ? " - #{description}" : '')
      else
        "Failed to set conversation feedback to '#{state}' state"
      end
    rescue StandardError => e
      "Failed to set conversation state: #{e.message}"
    end
  end

  # Set custom color and effect for LED ring
  def self.set_custom_color(color:, brightness: 150, effect: 'solid', description: nil)
    # Validate brightness
    brightness = brightness.to_i
    brightness = [[brightness, 0].max, 255].min  # Clamp between 0-255
    
    # Validate effect
    valid_effects = %w[solid pulse_slow pulse_fast flash fade_out]
    effect_sym = effect.to_sym
    unless valid_effects.include?(effect.to_s)
      effect_sym = :solid
      effect = 'solid'
    end
    
    # Default description
    description ||= "Custom #{effect} effect in #{color}"

    begin
      feedback_service = Services::ConversationFeedbackService.new
      success = feedback_service.set_custom_color(
        color, 
        brightness: brightness, 
        effect: effect_sym, 
        description: description
      )
      
      Services::LoggerService.log_api_call(
        service: 'conversation_feedback_tool',
        endpoint: 'set_custom_color',
        color: color,
        brightness: brightness,
        effect: effect,
        success: success
      )

      if success
        "Set LED ring to #{color} with #{effect} effect at #{brightness} brightness"
      else
        "Failed to set custom LED color"
      end
    rescue StandardError => e
      "Failed to set custom color: #{e.message}"
    end
  end

  # Set mood-based color (convenience method)
  def self.set_mood(mood:, brightness: 150)
    mood_colors = {
      'happy' => '#FFFF00',     # Yellow
      'excited' => '#FF00FF',   # Magenta
      'calm' => '#0080FF',      # Blue
      'mysterious' => '#8000FF', # Purple
      'energetic' => '#FF4000',  # Orange-red
      'peaceful' => '#00FF80',   # Green
      'romantic' => '#FF0080',   # Pink
      'focused' => '#FFFFFF',    # White
      'playful' => '#00FFFF',    # Cyan
      'warm' => '#FF8040'        # Warm orange
    }

    color = mood_colors[mood.downcase] || mood  # Use mood as color if not found in presets
    
    set_custom_color(
      color: color, 
      brightness: brightness, 
      effect: 'solid',
      description: "#{mood.capitalize} mood lighting"
    )
  end

  # Turn off LED ring
  def self.turn_off
    begin
      feedback_service = Services::ConversationFeedbackService.new
      success = feedback_service.turn_off
      
      Services::LoggerService.log_api_call(
        service: 'conversation_feedback_tool',
        endpoint: 'turn_off',
        success: success
      )

      if success
        'LED ring turned off'
      else
        'Failed to turn off LED ring'
      end
    rescue StandardError => e
      "Failed to turn off LED ring: #{e.message}"
    end
  end

  # Get current LED ring status
  def self.get_status
    begin
      feedback_service = Services::ConversationFeedbackService.new
      status = feedback_service.get_status
      
      Services::LoggerService.log_api_call(
        service: 'conversation_feedback_tool',
        endpoint: 'get_status'
      )

      if status[:state] == 'unavailable'
        'LED ring is unavailable'
      elsif status[:state] == 'error'
        "LED ring error: #{status[:error]}"
      else
        result = ["LED ring: #{status[:state]}"]
        result << "Brightness: #{status[:brightness]}" if status[:brightness]
        result << "Color: #{status[:rgb_color]}" if status[:rgb_color]
        result << "Device: #{status[:friendly_name]}" if status[:friendly_name]
        
        result.join(' | ')
      end
    rescue StandardError => e
      "Failed to get LED ring status: #{e.message}"
    end
  end

  # List all available conversation states
  def self.list_states
    result = []
    result << '=== CONVERSATION FEEDBACK STATES ==='
    
    Services::ConversationFeedbackService::CONVERSATION_STATES.each do |state, config|
      result << "#{state}: #{config[:color]} - #{config[:description]}"
      result << "  Effect: #{config[:effect]}, Brightness: #{config[:brightness]}"
    end
    
    result << ''
    result << '=== AVAILABLE EFFECTS ==='
    result << 'solid - Steady color'
    result << 'pulse_slow - Slow breathing effect'
    result << 'pulse_fast - Fast pulsing'
    result << 'flash - Quick flashing for alerts'
    result << 'fade_out - Gradual fade to dim'
    
    result.join("\n")
  end

  # Quick convenience methods for common states
  def self.listening
    set_state(state: 'listening')
  end

  def self.thinking  
    set_state(state: 'thinking')
  end

  def self.speaking
    set_state(state: 'speaking')
  end

  def self.completed
    set_state(state: 'completed')
  end

  def self.error_state
    set_state(state: 'error')
  end

  def self.idle
    set_state(state: 'idle')
  end
end