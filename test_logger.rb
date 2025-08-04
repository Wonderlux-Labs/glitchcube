#!/usr/bin/env ruby
# frozen_string_literal: true

# Test the logger service to ensure it works properly

require_relative 'lib/services/logger_service'

puts 'Testing logger service...'
puts "Current directory: #{Dir.pwd}"
puts "APP_ROOT: #{ENV['APP_ROOT'] || 'not set'}"

begin
  Services::LoggerService.setup_loggers
  puts '✅ Logger setup successful'

  # Test general logging
  Services::LoggerService.general.info('Test log message')
  puts '✅ General logging works'

  # Test API logging
  Services::LoggerService.log_api_call(
    service: 'test',
    endpoint: '/test',
    status: 200,
    duration: 100
  )
  puts '✅ API logging works'

  # Test request logging
  Services::LoggerService.log_request(
    method: 'GET',
    path: '/test',
    status: 200,
    duration: 50
  )
  puts '✅ Request logging works'

  # Check if log files were created
  log_dir = File.join(ENV['APP_ROOT'] || Dir.pwd, 'logs')
  if File.directory?(log_dir)
    puts "\n📁 Log directory contents:"
    Dir.glob(File.join(log_dir, '*')).each do |file|
      puts "   - #{File.basename(file)} (#{File.size(file)} bytes)"
    end
  else
    puts "⚠️  Log directory not found at: #{log_dir}"
  end
rescue StandardError => e
  puts "❌ Logger test failed: #{e.message}"
  puts e.backtrace[0..5]
end
