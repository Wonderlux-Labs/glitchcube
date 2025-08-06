# frozen_string_literal: true

require 'sidekiq'
require 'sidekiq-cron'

# Configure Sidekiq
Sidekiq.configure_server do |config|
  config.redis = { url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0') }

  # Load cron jobs with startup logging
  schedule_file = 'config/sidekiq_cron.yml'

  if File.exist?(schedule_file) && Sidekiq.server?
    cron_schedule = YAML.load_file(schedule_file)
    Sidekiq::Cron::Job.load_from_hash(cron_schedule)
    
    puts "🔥 Sidekiq-cron jobs loaded at startup:"
    cron_schedule.each do |job_name, job_config|
      status = if job_config.key?('active') && !job_config['active']
        '❌ DISABLED'
      else
        '✅ ACTIVE'
      end
      puts "   #{status} #{job_name}: #{job_config['cron']} (#{job_config['description']})"
    end
    
    # Also show runtime status after loading
    config.on(:startup) do
      sleep 1 # Give jobs time to load
      puts "\n📊 Sidekiq-cron job status:"
      Sidekiq::Cron::Job.all.each do |job|
        enabled = job.enabled? ? '✅ ENABLED' : '❌ DISABLED'
        last_run = job.last_enqueue_time ? job.last_enqueue_time.strftime('%Y-%m-%d %H:%M:%S') : 'Never'
        puts "   #{enabled} #{job.name}: #{job.cron} (Last: #{last_run})"
      end
      puts
    end
  else
    puts "⚠️  No sidekiq_cron.yml file found or not in server mode"
  end
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
