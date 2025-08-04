# frozen_string_literal: true

require 'desiru/jobs/scheduler'
require_relative '../../lib/jobs/beacon_heartbeat_job'

# Initialize the Desiru scheduler
scheduler = Desiru::Jobs::Scheduler.instance

# Schedule beacon heartbeat if enabled
if GlitchCube.config.beacon.enabled
  # Schedule heartbeat every 5 minutes
  Jobs::BeaconHeartbeatJob.schedule(
    name: 'beacon_heartbeat',
    cron: 'every 5 minutes'
  )

  # Schedule daily backup reminder at 3 AM
  Jobs::BeaconAlertJob.schedule(
    name: 'daily_backup_reminder',
    cron: '0 3 * * *', # Daily at 3 AM
    args: ['Daily backup reminder - Glitch Cube is still running', 'info']
  )

  puts '📡 Beacon heartbeat scheduled to run every 5 minutes'
  puts '📡 Daily backup reminder scheduled for 3 AM'
end

# Start the scheduler when the app starts
at_exit do
  scheduler.stop if scheduler.running?
end

# Start scheduler in a separate thread
Thread.new do
  sleep 2 # Give the app time to fully initialize
  scheduler.start unless scheduler.running?
  puts '⏰ Desiru scheduler started'
end
