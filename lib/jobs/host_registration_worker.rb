# frozen_string_literal: true

class HostRegistrationWorker
  include Sidekiq::Job

  # Run every 5 minutes to ensure registration stays current
  sidekiq_options retry: 3, queue: :default

  def perform
    Services::HostRegistrationService.register_with_home_assistant
  end
end
