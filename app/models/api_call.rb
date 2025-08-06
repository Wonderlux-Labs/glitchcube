# frozen_string_literal: true

class ApiCall < ActiveRecord::Base
  validates :service, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :by_service, ->(service) { where(service: service) }
  scope :successful, -> { where(error_message: nil) }
  scope :failed, -> { where.not(error_message: nil) }

  # Quick stats
  def self.stats_for_period(start_time, end_time = Time.current)
    where(created_at: start_time..end_time)
      .group(:service)
      .pluck(
        :service,
        'COUNT(*)',
        'AVG(duration_ms)',
        'SUM(tokens_used)',
        'COUNT(CASE WHEN error_message IS NOT NULL THEN 1 END)'
      ).map do |service, count, avg_duration, total_tokens, error_count|
        {
          service: service,
          total_calls: count,
          avg_duration_ms: avg_duration&.round(2),
          total_tokens: total_tokens || 0,
          error_count: error_count,
          success_rate: ((count - error_count).to_f / count * 100).round(2)
        }
      end
  end
end
