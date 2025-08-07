#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for beacon service with Desiru scheduler

require 'bundler/setup'
require 'dotenv/load'
require 'desiru'

# Configure Desiru
Desiru.configure do |config|
  config.default_model = Desiru::Models::OpenRouter.new(
    api_key: ENV.fetch('OPENROUTER_API_KEY', nil),
    model: ENV.fetch('DEFAULT_AI_MODEL', 'google/gemini-2.5-flash')
  )
end

# Load beacon service and job
require_relative '../lib/services/beacon_service'
require_relative '../lib/jobs/beacon_heartbeat_job'

puts '🧪 Testing Beacon Service with Desiru Scheduler'
puts '=' * 50

# Test 1: Direct beacon service test
puts "\n1️⃣ Testing direct beacon service..."
beacon = Services::BeaconService.new

if ENV['BEACON_URL'] && !ENV['BEACON_URL'].empty?
  puts "   Beacon URL: #{ENV['BEACON_URL']}"
  puts '   Sending test heartbeat...'

  success = beacon.send_heartbeat
  puts success ? '   ✅ Heartbeat sent successfully!' : '   ❌ Heartbeat failed!'
else
  puts '   ⚠️  BEACON_URL not configured - skipping test'
end

# Test 2: Job execution test
puts "\n2️⃣ Testing beacon job execution..."
job = Jobs::BeaconHeartbeatJob.new
job.perform("test-job-#{Time.now.to_i}")
puts '   ✅ Job executed'

# Test 3: Scheduler test
puts "\n3️⃣ Testing Desiru scheduler..."
scheduler = Desiru::Jobs::Scheduler.instance

# Schedule a test heartbeat to run every 10 seconds
Jobs::BeaconHeartbeatJob.schedule(
  name: 'test_heartbeat',
  cron: '10' # Every 10 seconds
)

puts '   ✅ Job scheduled to run every 10 seconds'
puts '   Starting scheduler...'

scheduler.start

puts "\n⏰ Scheduler is running. Watch for heartbeat messages every 10 seconds."
puts 'Press Ctrl+C to stop...'

begin
  sleep
rescue Interrupt
  puts "\n\n🛑 Stopping scheduler..."
  scheduler.stop
  Jobs::BeaconHeartbeatJob.unschedule(name: 'test_heartbeat')
  puts '✅ Test completed'
end
