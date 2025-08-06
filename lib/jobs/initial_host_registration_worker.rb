# frozen_string_literal: true

require_relative '../services/host_registration_service'

class InitialHostRegistrationWorker
  include Sidekiq::Job

  sidekiq_options retry: 10, queue: :default

  def perform
    # Try to register with retry loop
    success = Services::HostRegistrationService.register_with_retry_loop

    if success
      puts '✅ Initial registration successful - regular updates handled by cron job'
    else
      puts '❌ Initial registration failed - will retry via Sidekiq retry mechanism'
      raise 'Failed to register with Home Assistant after all attempts'
    end
  end
end
