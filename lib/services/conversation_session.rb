# frozen_string_literal: true

require 'securerandom'

module Services
  # Manages conversation sessions using ActiveRecord models
  # Provides a clean interface for conversation context management
  class ConversationSession
    MAX_CONTEXT_MESSAGES = 20 # How many messages to include in LLM context

    attr_reader :conversation, :session_id

    class << self
      # Find existing session or create new one
      def find_or_create(session_id: nil, context: {})
        session_id ||= SecureRandom.uuid

        # Use ActiveRecord to find or create
        conversation = ::Conversation.find_or_create_by(session_id: session_id) do |c|
          c.source = context[:source] || 'api'
          c.persona = context[:persona] || 'neutral'
          c.started_at = Time.current
          c.metadata = context.except(:session_id, :source, :persona)
        end

        new(conversation)
      end

      # Find existing session (returns nil if not found)
      def find(session_id)
        return nil unless session_id

        conversation = ::Conversation.find_by(session_id: session_id)
        conversation ? new(conversation) : nil
      end
    end

    def initialize(conversation)
      @conversation = conversation
      @session_id = conversation.session_id
    end

    # Check if session exists
    def exists?
      !@conversation.nil?
    end

    # Add message to conversation
    def add_message(role:, content:, **extra)
      message = @conversation.add_message(
        role: role,
        content: content,
        **extra
      )

      # Update conversation totals if assistant message
      if role == 'assistant'
        updates = {
          total_cost: @conversation.total_cost + (extra[:cost] || 0),
          total_tokens: @conversation.total_tokens +
                        (extra[:prompt_tokens] || 0) +
                        (extra[:completion_tokens] || 0)
        }
        updates[:persona] = extra[:persona] if extra[:persona]
        @conversation.update!(updates)
      end

      message
    end

    # Get messages for LLM context
    def messages_for_llm(limit: nil)
      limit ||= max_context_messages

      # Get recent messages from database
      recent_messages = @conversation.messages
        .order(created_at: :desc)
        .limit(limit)
        .reverse # Oldest first for context

      # Format for LLM API
      recent_messages.map do |msg|
        {
          role: msg.role,
          content: msg.content
        }
      end
    end

    # Get conversation summary
    def summary
      @conversation.summary
    end

    # Get metadata (for compatibility)
    def metadata
      {
        source: @conversation.source,
        started_at: @conversation.started_at,
        interaction_count: @conversation.message_count,
        total_cost: @conversation.total_cost,
        total_tokens: @conversation.total_tokens,
        last_persona: @conversation.persona,
        context: @conversation.metadata
      }
    end

    # End conversation
    def end_conversation(reason: nil)
      @conversation.end!
      @conversation.update!(end_reason: reason) if reason

      # Optionally trigger background job for summarization
      ConversationSummaryJob.perform_async(@session_id) if defined?(ConversationSummaryJob)

      true
    end

    # Save changes (for compatibility - ActiveRecord auto-saves)
    def save
      @conversation.save
    end

    private

    def max_context_messages
      GlitchCube.config.conversation&.max_context_messages || MAX_CONTEXT_MESSAGES
    end
  end
end
