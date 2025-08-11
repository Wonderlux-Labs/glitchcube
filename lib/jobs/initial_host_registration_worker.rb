# frozen_string_literal: true

class InitialHostRegistrationWorker
  include Sidekiq::Job

  sidekiq_options retry: 10, queue: :default

  def perform
    # Try to register with retry loop
    success = Services::HostRegistrationService.register_with_retry_loop

    if success
      Services::SimpleLogger.info(
        '✅ Initial registration successful - regular updates handled by cron job',
        tagged: %i[host_registration startup]
      )
    else
      Services::SimpleLogger.error(
        '❌ Initial registration failed - will retry via Sidekiq retry mechanism',
        tagged: %i[host_registration startup error]
      )
      raise 'Failed to register with Home Assistant after all attempts'
    end
  end
end
