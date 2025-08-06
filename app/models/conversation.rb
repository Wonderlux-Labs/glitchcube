# frozen_string_literal: true

class Conversation < ActiveRecord::Base
  has_many :messages, dependent: :destroy

  validates :session_id, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :active, -> { where(ended_at: nil) }
  scope :by_persona, ->(persona) { where(persona: persona) }

  # End the conversation
  def end!
    update!(ended_at: Time.current) unless ended_at
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

  # Get conversation summary
  def summary
    {
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
    totals = messages.select('SUM(prompt_tokens + completion_tokens) as tokens, SUM(cost) as cost').first
    update!(
      total_tokens: totals.tokens || 0,
      total_cost: totals.cost || 0.0
    )
  end
end
