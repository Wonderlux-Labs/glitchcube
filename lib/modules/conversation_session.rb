# frozen_string_literal: true

require_relative '../helpers/session_storage'
require 'securerandom'

# Session management for conversations using flexible storage backend
class ConversationSession
  attr_reader :session_id

  def initialize(session_id = nil)
    @session_id = session_id || SecureRandom.uuid
    
    # Initialize session storage if not already configured
    Helpers::SessionStorage.configure! unless storage_configured?
  end

  # Add message to conversation history
  def add_message(message, response, mood, suggested_mood)
    messages = get_messages
    
    message_data = {
      message: message,
      response: response,
      mood: mood,
      suggested_mood: suggested_mood,
      timestamp: Time.now.iso8601,
      from_user: true
    }
    
    messages << message_data
    
    # Keep only the last N messages (configurable)
    max_messages = GlitchCube.config.conversation.max_session_messages
    messages = messages.last(max_messages) if messages.length > max_messages
    
    set_data(:messages, messages)
  end

  # Get conversation history
  def get_messages
    get_data(:messages) || []
  end

  # Get message count
  def message_count
    get_messages.length
  end

  # Set session context data
  def set_context(key, value)
    context = get_context
    context[key.to_s] = value
    set_data(:context, context)
  end

  # Get session context data
  def get_context
    get_data(:context) || {}
  end

  # Get specific context value
  def get_context_value(key)
    get_context[key.to_s]
  end

  # Set current mood
  def set_mood(mood)
    set_data(:current_mood, mood)
  end

  # Get current mood
  def get_mood
    get_data(:current_mood) || 'neutral'
  end

  # Update interaction count
  def increment_interaction_count
    count = get_interaction_count + 1
    set_data(:interaction_count, count)
    count
  end

  # Get interaction count
  def get_interaction_count
    get_data(:interaction_count) || 0
  end

  # Check if conversation should be summarized
  def should_summarize?(message = nil)
    # Summarize if:
    # 1. User says goodbye/bye/leaving
    # 2. Conversation has max messages
    # 3. Session has been idle for too long

    if message
      goodbye_words = %w[goodbye bye leaving done exit quit thanks]
      return true if goodbye_words.any? { |word| message.downcase.include?(word) }
    end

    message_count >= GlitchCube.config.conversation.max_session_messages
  end

  # Get session summary for persistence
  def get_summary
    {
      session_id: @session_id,
      message_count: message_count,
      interaction_count: get_interaction_count,
      current_mood: get_mood,
      context: get_context,
      created_at: get_data(:created_at) || Time.now.iso8601,
      updated_at: Time.now.iso8601
    }
  end

  # Check if session exists
  def exists?
    Helpers::SessionStorage.exists?(@session_id)
  end

  # Clear session data
  def clear!
    Helpers::SessionStorage.clear_session(@session_id)
  end

  # Update last activity timestamp
  def touch!
    set_data(:last_activity, Time.now.iso8601)
  end

  # Get last activity time
  def last_activity
    timestamp = get_data(:last_activity)
    timestamp ? Time.parse(timestamp) : nil
  rescue ArgumentError
    nil
  end

  # Check if session is idle
  def idle?(timeout_minutes = 30)
    last = last_activity
    return true unless last
    
    Time.now - last > (timeout_minutes * 60)
  end

  private

  def set_data(key, value, ttl: 7200) # 2 hours default TTL
    touch! unless key == :last_activity
    Helpers::SessionStorage.set(@session_id, key, value, ttl: ttl)
  end

  def get_data(key)
    Helpers::SessionStorage.get(@session_id, key)
  end

  def storage_configured?
    Helpers::SessionStorage.instance_variable_get(:@storage_backend)
  end

  # Class methods for session management
  class << self
    # Create new session
    def create(session_id = nil)
      session = new(session_id)
      session.set_data(:created_at, Time.now.iso8601)
      session
    end

    # Find existing session or create new one
    def find_or_create(session_id)
      session = new(session_id)
      
      if session.exists?
        session
      else
        create(session_id)
      end
    end

    # Cleanup expired sessions
    def cleanup_expired!
      puts "🧹 Cleaning up expired conversation sessions..."
      Helpers::SessionStorage.cleanup_expired!
    end

    # Get session storage statistics
    def stats
      Helpers::SessionStorage.stats
    end
  end
end