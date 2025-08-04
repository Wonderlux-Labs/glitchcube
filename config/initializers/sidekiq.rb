# frozen_string_literal: true

require 'sidekiq'
require 'sidekiq/cron/job'

# Configure Sidekiq for minimal resource footprint on single device
Sidekiq.configure_server do |config|
  config.redis = { url: GlitchCube.config.redis_url || 'redis://localhost:6379/0' }

  # Minimal resource configuration for art installation
  config.concurrency = 1 # Single worker thread
  config.queues = ['default'] # Single queue

  # Sidekiq-cron configuration is done via Sidekiq::Cron directly

  # Load cron jobs after Sidekiq starts
  config.on(:startup) do
    schedule = {
      'repeating_jobs' => {
        'cron' => '*/5 * * * *', # Every 5 minutes
        'class' => 'RepeatingJobsHandler',
        'description' => 'Unified handler for all repeating background services',
        'active_job' => false
      }
    }

    Sidekiq::Cron::Job.load_from_hash(schedule)

    puts '✅ Sidekiq-cron loaded: RepeatingJobsHandler scheduled every 5 minutes'
    puts "   Available services: #{RepeatingJobsHandler::SERVICES.keys.join(', ')}"
  end
end

Sidekiq.configure_client do |config|
  config.redis = { url: GlitchCube.config.redis_url || 'redis://localhost:6379/0' }
end

# Add middleware for error tracking and logging
Sidekiq.configure_server do |config|
  config.error_handlers << proc do |exception, context|
    puts "❌ Sidekiq job failed: #{exception.message}"
    puts "   Context: #{context}"
    puts "   Backtrace: #{exception.backtrace&.first(5)&.join("\n   ")}"
  end
end

puts '✅ Sidekiq configured with minimal footprint for art installation'
