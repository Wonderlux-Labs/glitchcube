# frozen_string_literal: true

class HostRegistrationWorker
  include Sidekiq::Job

  # Run every 5 minutes to ensure registration stays current
  sidekiq_options retry: 3, queue: :default

  def perform(initial_registration: false)
    if initial_registration
      # Try to register with retry loop for initial registration
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
    else
      # Regular registration update
      Services::HostRegistrationService.register_with_home_assistant
    end
  end
end
