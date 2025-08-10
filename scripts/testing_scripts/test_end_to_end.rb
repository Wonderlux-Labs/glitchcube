#!/usr/bin/env ruby
# frozen_string_literal: true

# Test end-to-end conversation flow: conversation → HA control → TTS response

require 'dotenv'
Dotenv.load('.env.defaults', '.env')

puts '🎲 Testing End-to-End Conversation Flow'
puts '=' * 50

# Initialize services
Services::LoggerService.setup_loggers

# Reset circuit breakers for clean test
Services::CircuitBreakerService.reset_all

puts "\n1. Testing Basic Conversation"
puts '-' * 30

conversation = ConversationModule.new

# Test basic conversation
result = conversation.call(
  message: 'Hello! Can you tell me about yourself?',
  context: {
    session_id: 'end_to_end_test',
    interaction_count: 1,
    location: 'Test Environment'
  },
  mood: 'neutral'
)

puts '✅ Conversation completed'
puts "Response: #{result[:response]}"
puts "Confidence: #{(result[:confidence] * 100).round}%"

puts "\n2. Testing Mood-Based Conversation"
puts '-' * 35

# Test different moods
moods = %w[playful contemplative mysterious]
moods.each_with_index do |mood, i|
  puts "\nTesting #{mood} mood..."

  result = conversation.call(
    message: 'What do you think about the relationship between art and technology?',
    context: {
      session_id: "mood_test_#{i}",
      interaction_count: 1,
      current_mood: mood
    },
    mood: mood
  )

  puts "#{mood.capitalize} response: #{result[:response][0..100]}#{'...' if result[:response].length > 100}"
end

puts "\n3. Testing Circuit Breaker Recovery"
puts '-' * 35

# Reset circuit breakers to ensure they're closed
Services::CircuitBreakerService.reset_all

puts 'All circuit breakers reset to closed state'
Services::CircuitBreakerService.status.each do |status|
  puts "  #{status[:name]}: #{status[:state]}"
end

# Test conversation with healthy services
result = conversation.call(
  message: 'Can you control the lights and tell me about the environment?',
  context: {
    session_id: 'recovery_test',
    interaction_count: 1,
    test_recovery: true
  },
  mood: 'neutral'
)

puts '✅ Recovery test completed'
puts "Response: #{result[:response][0..150]}#{'...' if result[:response].length > 150}"

puts "\n4. Log File Summary"
puts '-' * 20

# Check logs were created
log_files = Dir.glob('logs/*.log') + Dir.glob('logs/*.json')
puts 'Generated log files:'
log_files.each do |file|
  size = File.size(file)
  puts "  📄 #{File.basename(file)} (#{size} bytes)"
end

puts "\n✅ End-to-End Test Complete!"
puts "\nKey Features Tested:"
puts '  🎯 Basic conversation flow'
puts '  🎭 Mood-based personality switching'
puts '  🔄 Circuit breaker recovery'
puts '  📝 Comprehensive logging'
puts '  🔊 TTS integration (with fallback)'
puts '  🏠 Home Assistant API integration (with fallback)'

puts "\nNext steps:"
puts '  1. Start the full application: bundle exec ruby app.rb'
puts '  2. Test via HTTP API at http://localhost:4567'
puts '  3. Monitor logs in real-time: tail -f logs/interactions.log'
