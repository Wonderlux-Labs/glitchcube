# frozen_string_literal: true

class Summary < ActiveRecord::Base
  SUMMARY_TYPES = %w[personal interaction event daily].freeze
  PERIODS = %w[hourly daily].freeze

  validates :summary_type, presence: true, inclusion: { in: SUMMARY_TYPES }
  validates :period, presence: true, inclusion: { in: PERIODS }
  validates :content, presence: true

  scope :hourly, -> { where(period: 'hourly') }
  scope :daily, -> { where(period: 'daily') }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(summary_type: type) }

  def self.last_hourly_summaries(limit = 24)
    hourly.recent.limit(limit)
  end
end
