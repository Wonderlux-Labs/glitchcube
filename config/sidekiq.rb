# frozen_string_literal: true

require 'sidekiq'
require 'sidekiq-cron'

# Configure Sidekiq
Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }

  # Load cron jobs
  schedule_file = 'config/sidekiq_cron.yml'

  Sidekiq::Cron::Job.load_from_hash YAML.load_file(schedule_file) if File.exist?(schedule_file) && Sidekiq.server?
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }
end

# Configure job retry behavior
Sidekiq.default_job_options = {
  'retry' => 3,
  'backtrace' => true
}

# Add middleware for logging
class BeaconLoggingMiddleware
  def call(worker, _job, _queue)
    puts "[Beacon] Starting #{worker.class} job" if worker.class.to_s.include?('Beacon')
    yield
  end
end

Sidekiq.configure_server do |config|
  config.server_middleware do |chain|
    chain.add BeaconLoggingMiddleware
  end
end
