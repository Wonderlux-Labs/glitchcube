# frozen_string_literal: true

require 'securerandom'
require_relative '../../lib/modules/globals'
# abstract class

class ConversationSession
  MAX_CONTEXT_MESSAGES = 20 # How many messages to include in LLM context

  attr_reader :conversation, :session_id

  class << self
    # Find existing session or create new one
    def find_or_create(session_id: nil, context: {})
      session_id ||= SecureRandom.uuid

      existing = Conversation.find_by(session_id: session_id)
      if existing && existing.updated_at < 3.minutes.ago
        existing.end!
      end

      # Use ActiveRecord to find or create
      conversation = existing || Conversation.create!(
        session_id: session_id,
        source: context[:source] || 'api',
        persona: Modules::Globals.persona,
        started_at: Time.current,
        metadata: context.except(:session_id, :source, :persona)
      )
      # Verify it's in the database
      raise "Failed to persist conversation with session_id: #{session_id}" unless Conversation.exists?(session_id: session_id)

      new(conversation)
    end

    private
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

    update_conversation_stats(extra) if role == 'assistant'

    message
  end

  # Delegate methods to underlying conversation model
  def messages
    @conversation.messages
  end

  def created_at
    @conversation.created_at
  end

  # Get messages for LLM context
  def messages_for_llm(limit: nil)
    limit ||= max_context_messages
    recent_messages = fetch_recent_messages(limit)
    format_messages_for_llm(recent_messages)
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
  # rubocop:disable Naming/PredicateMethod
  def end_conversation(reason: nil)
    @conversation.end!
    @conversation.update!(end_reason: reason) if reason

    true
  end
  # rubocop:enable Naming/PredicateMethod

  # Save changes (for compatibility - ActiveRecord auto-saves)
  def save
    @conversation.save
  end

  private

  def update_conversation_stats(extra)
    updates = build_conversation_updates(extra)
    updates[:flow_data] = update_flow_data(extra) if should_update_flow_data?(extra)
    @conversation.update!(updates)
  end

  def build_conversation_updates(extra)
    updates = {
      total_cost: @conversation.total_cost + (extra[:cost] || 0),
      total_tokens: @conversation.total_tokens +
                    (extra[:prompt_tokens] || 0) +
                    (extra[:completion_tokens] || 0)
    }
    updates[:persona] = extra[:persona] if extra[:persona]
    updates
  end

  def should_update_flow_data?(extra)
    extra[:metadata] && extra[:metadata][:inner_thoughts].present?
  end

  def update_flow_data(extra)
    flow_data = @conversation.flow_data || {}
    flow_data['inner_thoughts'] ||= []
    flow_data['inner_thoughts'] << {
      'timestamp' => Time.now.iso8601,
      'persona' => extra[:persona],
      'thought' => extra[:metadata][:inner_thoughts]
    }
    flow_data
  end

  def fetch_recent_messages(limit)
    @conversation.messages
                 .order(created_at: :desc)
                 .limit(limit)
                 .reverse # Oldest first for context
  end

  def format_messages_for_llm(messages)
    messages.map do |msg|
      {
        role: msg.role,
        content: msg.content
      }
    end
  end

  def max_context_messages
    GlitchCube.config.conversation&.max_context_messages || MAX_CONTEXT_MESSAGES
  end
end
