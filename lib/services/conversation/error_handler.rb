# frozen_string_literal: true

module Services
  module Conversation
    # Handles different types of errors in conversations and generates appropriate responses
    class ErrorHandler
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

      TOOL_ERROR_RESPONSES = [
        'I ran into a problem trying to use one of my tools. Maybe we can try a different approach?',
        "It seems there was an issue with a tool I was using. Let's try that again.",
        "I couldn't quite get that tool to work. How about we try something else?"
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
        Services::Logging::SimpleLogger.debug("Handling error of type: #{error.class.name}", tagged: %i[conversation error_handling])
        Services::Logging::SimpleLogger.debug("Error message: #{error.message}", tagged: %i[conversation error_handling])
        Services::Logging::SimpleLogger.debug("Error backtrace: #{error.backtrace&.first(3)&.join(', ')}", tagged: %i[conversation error_handling])

        response = case error
                   when Services::Llm::LLMService::RateLimitError
                     Services::Logging::SimpleLogger.debug('Matched RateLimitError case', tagged: %i[conversation error_handling])
                     handle_rate_limit
                   when Services::Conversation::Errors::ToolExecutionError
                     Services::Logging::SimpleLogger.debug('Matched ToolExecutionError case', tagged: %i[conversation error_handling])
                     handle_tool_execution_error
                   when Services::Llm::LLMService::LLMError
                     Services::Logging::SimpleLogger.debug('Matched LLMError case', tagged: %i[conversation error_handling])
                     handle_llm_error
                   else
                     Services::Logging::SimpleLogger.debug('Matched general error case', tagged: %i[conversation error_handling])
                     handle_general_error
                   end

        log_error
        response
      end

      private

      attr_reader :error, :session, :message, :persona, :context

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

      def handle_tool_execution_error
        response_text = TOOL_ERROR_RESPONSES.first # Use first for consistent tests
        record_error_response(response_text)

        {
          response: response_text,
          persona: persona,
          error: 'tool_execution_error',
          error_details: {
            tool_name: error.tool_name,
            original_error: error.original_error&.message
          },
          conversation_id: session&.session_id,
          session_id: session&.session_id,
          continue_conversation: false
        }
      end

      def handle_general_error
        response_text = GENERAL_ERROR_RESPONSES.first # Use first for consistent tests

        record_error_response(response_text)

        {
          response: response_text,
          persona: persona,
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
        Services::Logging::SimpleLogger.warn(
          'Could not record error response',
          tagged: %i[conversation error_recording],
          error: e.message
        )
      end

      def generate_offline_response
        # Use the persona system for consistent offline responses

        persona_instance = Personas::BasePersona.create(persona.to_s, context)
        persona_instance.generate_offline_response(message)
      rescue StandardError => e
        Services::Logging::SimpleLogger.warn(
          'Could not generate persona-specific offline response, using fallback',
          tagged: %i[conversation error_handling persona],
          error: e.message,
          persona: persona
        )

        # Fallback to generic response if persona system fails
        "I'm currently offline but still operational with limited capabilities. How can I help?"
      end

      def log_error
        # Log to SimpleLogger for debug visibility
        Services::Logging::SimpleLogger.error("Conversation error: #{error.class.name} - #{error.message}",
                                              tagged: %i[conversation error],
                                              error_class: error.class.name,
                                              persona: persona,
                                              session_id: session&.session_id)

        # Also track in SimpleLogger for production monitoring
        Services::Logging::SimpleLogger.error(
          'CONVERSATION_ERROR_TRACKING',
          tagged: %i[conversation error_tracking],
          service: 'ConversationModule',
          error_message: error.message,
          error_class: error.class.name
        )
      rescue StandardError => e
        Services::Logging::SimpleLogger.warn(
          'Could not log error',
          tagged: %i[conversation error_logging],
          error: e.message
        )
      end
    end
  end
end
