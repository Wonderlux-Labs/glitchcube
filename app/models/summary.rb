# frozen_string_literal: true

class Summary < ActiveRecord::Base
  SUMMARY_TYPES = %w[personal interaction event daily].freeze
  PERIODS = %w[hourly daily].freeze

  validates :summary_type, presence: true, inclusion: { in: SUMMARY_TYPES }
  validates :period, presence: true, inclusion: { in: PERIODS }
  validates :content, presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(summary_type: type) }
  scope :by_period, ->(period) { where(period: period) }

  # Dynamic scopes for all periods
  PERIODS.each do |period|
    scope period.to_sym, -> { where(period: period) }
  end

  # Dynamic scopes for all summary types
  SUMMARY_TYPES.each do |type|
    scope type.to_sym, -> { where(summary_type: type) }
  end

  def self.last_hourly_summaries(limit = 24)
    hourly.recent.limit(limit)
  end
end
