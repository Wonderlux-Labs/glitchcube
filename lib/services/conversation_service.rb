# frozen_string_literal: true

require_relative '../modules/conversation_module'

module Services
  class ConversationService
    attr_reader :conversation_module, :context

    def initialize(context: {})
      @conversation_module = ConversationModule.new
      @context = context
    end

    def process_message(message, mood: 'neutral')
      # Update interaction count
      @context[:interaction_count] = (@context[:interaction_count] || 0) + 1

      # Call the conversation module with message and current context
      result = conversation_module.call(
        message: message,
        context: @context,
        persona: mood
      )

      # No need to track mood changes - personas are scheduled

      result
    end

    def reset_context
      @context = {
        session_id: SecureRandom.uuid,
        interaction_count: 0,
        started_at: Time.now
      }
    end

    def add_context(key, value)
      @context[key] = value
    end

    def get_context
      @context.dup
    end
  end
end
