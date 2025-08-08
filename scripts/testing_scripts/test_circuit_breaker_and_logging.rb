#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for circuit breaker and logging functionality

# Load environment
require 'dotenv'
Dotenv.load('.env.defaults', '.env')

# Load dependencies
require_relative 'config/constants'
require_relative 'config/initializers/config'
require_relative 'lib/services/circuit_breaker_service'
require_relative 'lib/services/logger_service'
require_relative 'lib/home_assistant_client'
require_relative 'lib/modules/conversation_module'

puts '🧪 Testing Circuit Breaker and Logging System'
puts '=' * 60

# Initialize logger
Services::LoggerService.setup_loggers

puts "\n1. Testing Logger Service"
puts '-' * 30

# Test interaction logging
Services::LoggerService.log_interaction(
  user_message: 'Hello, Glitch Cube!',
  ai_response: 'Welcome to the testing phase! Ready to explore together?',
  mood: 'playful',
  confidence: 0.95,
  session_id: 'test_session_001',
  context: { test_mode: true, location: 'Test Lab' }
)

# Test API call logging
Services::LoggerService.log_api_call(
  service: 'home_assistant',
  endpoint: '/api/services/tts/speak',
  method: 'POST',
  status: 200,
  duration: 1250
)

# Test TTS logging
Services::LoggerService.log_tts(
  message: 'This is a test message for TTS logging',
  success: true,
  duration: 2300
)

# Test error tracking
Services::LoggerService.track_error('test_service', 'Simulated error for testing')
Services::LoggerService.track_error('test_service', 'Simulated error for testing') # Duplicate
Services::LoggerService.track_error('another_service', 'Different error type')

puts '✅ Logger tests completed - check logs/ directory'

puts "\n2. Testing Circuit Breaker Functionality"
puts '-' * 40

# Get circuit breakers
ha_breaker = Services::CircuitBreakerService.home_assistant_breaker
openrouter_breaker = Services::CircuitBreakerService.openrouter_breaker

puts 'Initial circuit breaker status:'
Services::CircuitBreakerService.status.each do |status|
  puts "  #{status[:name]}: #{status[:state]}"
end

puts "\n3. Simulating Circuit Breaker Failures"
puts '-' * 40

# Test Home Assistant circuit breaker by forcing failures
puts 'Testing Home Assistant circuit breaker...'
3.times do |i|
  ha_breaker.call do
    raise StandardError, "Simulated HA failure #{i + 1}"
  end
rescue StandardError => e
  puts "  Failure #{i + 1}: #{e.message}"
  Services::LoggerService.log_circuit_breaker(
    name: 'home_assistant',
    state: ha_breaker.state,
    reason: e.message
  )
end

puts "\nHome Assistant circuit breaker status after failures:"
puts "  State: #{ha_breaker.state}"
puts "  Failure count: #{ha_breaker.failure_count}"

# Try to call through open circuit breaker
puts "\nTesting open circuit breaker..."
begin
  ha_breaker.call do
    puts 'This should not execute'
  end
rescue CircuitBreaker::CircuitOpenError => e
  puts "✅ Circuit breaker correctly blocked call: #{e.message}"
  Services::LoggerService.log_circuit_breaker(
    name: 'home_assistant',
    state: :open,
    reason: 'Circuit breaker protection'
  )
end

puts "\n4. Testing Conversation Module with Offline Mode"
puts '-' * 50

# Test conversation with circuit breaker open (should use offline responses)
conversation = ConversationModule.new

# Force OpenRouter circuit breaker to fail
puts 'Opening OpenRouter circuit breaker...'
5.times do |i|
  openrouter_breaker.call do
    raise StandardError, "Simulated OpenRouter failure #{i + 1}"
  end
rescue StandardError => e
  puts "  OpenRouter failure #{i + 1}: #{e.message}"
end

puts "\nTesting conversation with OpenRouter circuit breaker open..."
result = conversation.call(
  message: 'Tell me about the art of conversation when systems fail',
  context: { session_id: 'test_session_002', test_mode: true },
  mood: 'contemplative'
)

puts "Response: #{result[:response]}"
puts "Confidence: #{result[:confidence]}"

puts "\n5. Error Statistics Summary"
puts '-' * 30

error_stats = Services::LoggerService.error_summary
puts "Total errors tracked: #{error_stats[:total_errors]}"
puts "Unique error types: #{error_stats[:unique_errors]}"
puts 'Errors by service:'
error_stats[:by_service].each do |service, count|
  puts "  #{service}: #{count}"
end

puts "\nTop errors:"
error_stats[:top_errors].first(3).each_with_index do |error, i|
  puts "  #{i + 1}. #{error[:service]}: #{error[:error]} (#{error[:count]} times)"
end

puts "\n6. Final Circuit Breaker Status"
puts '-' * 35

Services::CircuitBreakerService.status.each do |status|
  emoji = case status[:state]
          when :closed then '🟢'
          when :open then '🔴'
          when :half_open then '🟡'
          else '⚪'
          end

  puts "#{emoji} #{status[:name]}: #{status[:state].upcase}"
  puts "    Failures: #{status[:failure_count]}"
  puts "    Next attempt: #{status[:next_attempt_at] || 'N/A'}"
end

puts "\n✅ Circuit Breaker and Logging Test Complete!"
puts "\nCheck the following files:"
puts '  📄 logs/general.log - Structured application logs'
puts '  💬 logs/interactions.log - Human-readable conversation log'
puts '  🔌 logs/api_calls.log - API call performance log'
puts '  🔊 logs/tts.log - Text-to-speech activity log'
puts '  ❌ logs/errors.json - Error frequency tracking'
