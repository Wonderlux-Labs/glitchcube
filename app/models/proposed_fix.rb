# frozen_string_literal: true

require 'json'

# Model to store proposed fixes from the self-healing error handler
# These are NOT applied automatically - they're saved for human review
class ProposedFix < ActiveRecord::Base
  # Statuses for tracking review state
  STATUSES = %w[pending approved rejected applied ignored].freeze

  validates :error_class, presence: true
  validates :error_message, presence: true
  validates :confidence, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
  validates :status, inclusion: { in: STATUSES }

  scope :pending, -> { where(status: 'pending') }
  scope :high_confidence, -> { where('confidence >= ?', 0.8) }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_service, ->(service) { where(service_name: service) }

  # Store fix details as JSON
  serialize :fix_details, coder: JSON
  serialize :context_data, coder: JSON

  def apply!
    return false if status != 'pending'
    return false if GlitchCube.config.self_healing_dry_run

    # Actually apply the fix (only if not in dry-run mode)
    handler = Services::ErrorHandlingLLM.new
    result = handler.apply_and_deploy_fix(fix_details)

    if result[:deployed]
      update!(
        status: 'applied',
        applied_at: Time.current,
        commit_sha: result[:commit_sha]
      )
      true
    else
      update!(
        status: 'rejected',
        rejection_reason: result[:error]
      )
      false
    end
  end

  def approve!
    update!(status: 'approved', reviewed_at: Time.current)
  end

  def reject!(reason = nil)
    update!(
      status: 'rejected',
      reviewed_at: Time.current,
      rejection_reason: reason
    )
  end

  def ignore!
    update!(status: 'ignored', reviewed_at: Time.current)
  end

  def critical?
    fix_details&.dig('critical') == true
  end

  def error_summary
    "#{error_class}: #{error_message.truncate(100)}"
  end

  def fix_summary
    fix_details&.dig('description') || 'No description available'
  end

  def affected_files
    fix_details&.dig('files_modified') || []
  end
end
