# frozen_string_literal: true

class Conversation < ActiveRecord::Base
  has_many :messages, dependent: :destroy

  validates :session_id, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(ended_at: nil) }
  scope :by_persona, ->(persona) { where(persona: persona) }
  scope :finished, -> { where.not(ended_at: nil) }

  # Accessor for flow_data that ensures it's always a hash
  def flow_data
    self[:flow_data] ||= {}
  end

  # End the conversation
  def end!
    update!(ended_at: Time.current, continue_conversation: false) unless ended_at
  end

  def finished?
    ended_at.present?
  end

  # Returns the number of seconds since the conversation ended
  # Examples:
  #   - After 1 minute: returns 60.0
  #   - After 1 hour: returns 3600.0
  def finished_ago
    return nil unless ended_at

    Time.current - ended_at
  end

  # Check if conversation is active
  def active?
    ended_at.nil?
  end

  # Duration in seconds
  def duration
    return nil unless started_at

    (ended_at || Time.current) - started_at
  end

  # Add a message to the conversation
  def add_message(role:, content:, **attrs)
    messages.create!(
      role: role,
      content: content,
      **attrs
    )
    # NOTE: message_count is automatically incremented by counter_cache
  end

  def summary
    return @summary if @summary

    @summary = {
      session_id: session_id,
      message_count: message_count,
      persona: persona,
      total_cost: total_cost,
      total_tokens: total_tokens,
      duration: duration,
      started_at: started_at,
      ended_at: ended_at,
      last_message: messages.last&.content
    }
  end

  # Update costs and tokens
  def update_totals!
    # Use aggregate methods instead of raw SQL to avoid GROUP BY issues
    total_tokens = messages.sum('COALESCE(prompt_tokens, 0) + COALESCE(completion_tokens, 0)')
    total_cost = messages.sum('COALESCE(cost, 0)')

    update!(
      total_tokens: total_tokens,
      total_cost: total_cost
    )
  end
end
