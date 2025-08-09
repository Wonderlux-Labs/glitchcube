# frozen_string_literal: true

require 'securerandom'

module Services
  # Handles all post-conversation side effects like LED feedback, TTS, logging, and display updates
  class ConversationSideEffectHandler
    def initialize(result:, context:, session:, user_message:)
      @result = result
      @context = context
      @session = session
      @user_message = user_message
      @response_text = result[:response]
      @persona = result[:persona]
    end

    def execute
      set_feedback_state(:speaking)
      execute_tts
      log_interaction
      update_displays
      set_feedback_state(:completed)
    end

    private

    attr_reader :result, :context, :session, :user_message, :response_text, :persona

    def set_feedback_state(state)
      return unless context[:visual_feedback] != false

      Services::ConversationFeedbackService.new.set_state(state)
    rescue StandardError => e
      puts "Warning: LED feedback failed: #{e.message}" if debug_mode?
    end

    def execute_tts
      return unless should_execute_tts?

      if tts_tool_available?
        execute_tts_via_tool
      elsif debug_mode?
        puts '⚠️ TTS skipped - no speech_synthesis tool available'
      end
    rescue StandardError => e
      puts "Warning: TTS failed but conversation succeeded: #{e.message}"
    end

    def should_execute_tts?
      !response_text.nil? && !response_text.strip.empty?
    end

    def tts_tool_available?
      context[:tools]&.any? { |t| t.dig('function', 'name') == 'speech_synthesis' }
    end

    def execute_tts_via_tool
      entity_id = context[:entity_id] || 'media_player.square_voice'
      tool_calls = [{
        id: SecureRandom.hex(8),
        type: 'function',
        function: {
          name: 'speech_synthesis',
          arguments: {
            action: 'speak_text',
            params: {
              text: response_text,
              entity_id: entity_id
            }
          }.to_json
        }
      }]

      Services::ToolExecutor.execute(tool_calls, timeout: 10)
    end

    def log_interaction
      Services::LoggerService.log_interaction(
        user_message: user_message,
        ai_response: response_text,
        persona: persona,
        session_id: session.session_id
      )
    rescue StandardError => e
      puts "Warning: Interaction logging failed: #{e.message}"
    end

    def update_displays
      update_kiosk_display
    rescue StandardError => e
      puts "Warning: Display update failed: #{e.message}"
    end

    def update_kiosk_display
      return unless kiosk_enabled?

      Services::KioskService.update_mood(persona)
      Services::KioskService.update_interaction({
                                                  message: user_message,
                                                  response: response_text
                                                })
      Services::KioskService.add_inner_thought('Just shared something meaningful with a visitor')
    end

    def kiosk_enabled?
      defined?(Services::KioskService) &&
        Services::KioskService.respond_to?(:update_mood)
    end

    def debug_mode?
      GlitchCube.config.debug?
    end
  end
end
