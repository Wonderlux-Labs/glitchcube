#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for TTS service with improved error handling

require 'bundler/setup'
require 'dotenv'
Dotenv.load

# Load the app and dependencies
require_relative 'app'
require_relative 'lib/services/tts_service'

puts '=' * 50
puts 'TTS Service Test - Production Debugging'
puts '=' * 50

# Initialize the TTS service
tts = Services::TTSService.new

# Test messages
test_messages = [
  { text: 'Hello! Testing TTS service.', mood: nil },
  { text: "I'm feeling happy!", mood: :friendly },
  { text: 'This is exciting!', mood: :excited }
]

test_messages.each_with_index do |msg, idx|
  puts "\n📢 Test #{idx + 1}: #{msg[:text]}"
  puts "   Mood: #{msg[:mood] || 'neutral'}"

  begin
    result = if msg[:mood]
               tts.speak(msg[:text], mood: msg[:mood])
             else
               tts.speak(msg[:text])
             end

    if result
      puts '   ✅ Success!'
    else
      puts '   ❌ Failed (returned false)'
    end
  rescue StandardError => e
    puts "   💥 Error: #{e.class} - #{e.message}"
    puts '   Backtrace:'
    e.backtrace.first(5).each { |line| puts "      #{line}" }
  end

  # Wait between tests
  sleep(2) if idx < test_messages.length - 1
end

# Check circuit breaker status
puts "\n#{'=' * 50}"
puts 'Circuit Breaker Status:'
puts '=' * 50

status = Services::CircuitBreakerService.home_assistant_breaker.status
puts "State: #{status[:state]}"
puts "Failure count: #{status[:failure_count]}"
puts "Last failure: #{status[:last_failure_time]}"
puts "Next attempt in: #{(status[:next_attempt_at] - Time.now).round} seconds" if status[:next_attempt_at]

puts "\n✨ Test complete!"
