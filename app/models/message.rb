# frozen_string_literal: true

class Message < ActiveRecord::Base
  belongs_to :conversation, counter_cache: :message_count

  validates :role, presence: true, inclusion: { in: %w[user assistant system] }
  validates :content, presence: true

  scope :by_role, ->(role) { where(role: role) }
  scope :recent, -> { order(created_at: :desc) }
  scope :chronological, -> { order(created_at: :asc) }

  # Format for OpenRouter API
  def to_api_format
    {
      role: role,
      content: content
    }
  end

  # Calculate token cost (if we have token counts)
  def token_cost
    return nil unless prompt_tokens && completion_tokens && model_used

    # This would need to be updated with actual model pricing
    # For now, return a simple structure
    {
      prompt_tokens: prompt_tokens,
      completion_tokens: completion_tokens,
      total_tokens: prompt_tokens + completion_tokens,
      model: model_used
    }
  end
end
