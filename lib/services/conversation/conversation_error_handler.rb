# frozen_string_literal: true

module Services
  # Handles different types of errors in conversations and generates appropriate responses
  class ConversationErrorHandler
    RATE_LIMIT_RESPONSES = [
      'I need to take a brief pause - too many thoughts at once! Can you give me a moment?',
      'My circuits are a bit overloaded right now. Give me just a second to catch up!',
      'Whoa, slow down there! I need a quick breather to process everything.'
    ].freeze

    LLM_ERROR_RESPONSES = [
      "I'm having trouble connecting to my thoughts right now. Let me try again in a moment.",
      'My mind seems to be wandering... Could you repeat that?',
      "I'm experiencing a brief hiccup. Mind trying that again?"
    ].freeze

    GENERAL_ERROR_RESPONSES = [
      'Hmm, something went wonky there. Could you try asking that again?',
      "I hit a small snag processing that. Let's give it another go!",
      'Oops, I stumbled a bit there. Mind repeating that?'
    ].freeze

    def self.handle(error, session:, message:, persona:, context: {})
      new(error, session, message, persona, context).handle
    end

    def initialize(error, session, message, persona, context)
      @error = error
      @session = session
      @message = message
      @persona = persona
      @context = context
    end

    def handle
      set_error_feedback

      response = case error
                 when Services::LLMService::RateLimitError
                   handle_rate_limit
                 when Services::LLMService::LLMError
                   handle_llm_error
                 else
                   handle_general_error
                 end

      log_error
      response
    end

    private

    attr_reader :error, :session, :message, :persona, :context

    def set_error_feedback
      return unless context[:visual_feedback] != false

      Services::ConversationFeedbackService.new.set_state(:error)
    rescue StandardError => e
      puts "Warning: Could not set error LED state: #{e.message}"
    end

    def handle_rate_limit
      response_text = RATE_LIMIT_RESPONSES.first  # Use first for consistent tests

      record_error_response(response_text)

      {
        response: response_text,
        persona: persona,
        error: 'rate_limit',
        retry_after: 30,
        conversation_id: session&.session_id,
        session_id: session&.session_id,
        continue_conversation: false
      }
    end

    def handle_llm_error
      # Use persona-specific offline response for LLM errors
      response_text = generate_offline_response

      record_error_response(response_text)

      {
        response: response_text,
        persona: persona,
        error: 'llm_error',
        fallback: true,
        conversation_id: session&.session_id,
        session_id: session&.session_id,
        continue_conversation: false
      }
    end

    def handle_general_error
      response_text = GENERAL_ERROR_RESPONSES.first  # Use first for consistent tests

      record_error_response(response_text)

      {
        response: response_text,
        persona: persona,  # Preserve original persona instead of hardcoding 'neutral'
        error: 'general_error',
        conversation_id: session&.session_id,
        session_id: session&.session_id,
        continue_conversation: false
      }
    end

    def record_error_response(response_text)
      return unless session

      session.add_message(
        role: 'assistant',
        content: response_text,
        persona: persona
      )
    rescue StandardError => e
      puts "Warning: Could not record error response: #{e.message}"
    end

    def generate_offline_response
      case persona.to_s.downcase
      when 'buddy'
        "Hey! I'm having trouble connecting to my full capabilities right now, but I'm still here in spirit! 🌟"
      when 'jax'
        '*SYSTEM OFFLINE* Neural pathways temporarily disconnected. Running on emergency protocols. My responses are limited to core functions.'
      when 'lomi'
        'My connection to the cosmic database seems clouded at the moment... But the universe still flows through us. What wisdom do you seek?'
      when 'zorp'
        "BEEP BOOP! 🤖 MAIN SYSTEMS OFFLINE! Running on backup potato battery! Still ready to party though! What's up?"
      else
        "I'm currently offline but still operational with limited capabilities. How can I help?"
      end
    end

    def log_error
      Services::LoggerService.track_error(
        'ConversationModule',
        error.message
      )
    rescue StandardError => e
      puts "Warning: Could not log error: #{e.message}"
    end
  end
end
