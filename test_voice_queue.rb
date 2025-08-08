#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'app'

puts "=" * 60
puts "TESTING VOICE QUEUEING"
puts "=" * 60
puts "This will send multiple messages rapidly to test queueing"
puts "You should hear each message play sequentially without interruption"
puts "=" * 60

# Test messages from different characters
test_messages = [
  { character: :default, message: "First message from Default Jenny." },
  { character: :buddy, message: "Second message from BUDDY Davis!" },
  { character: :jax, message: "Third message from Jax Guy." },
  { character: :lomi, message: "Fourth message from LOMI Aria!" },
  { character: :default, message: "Fifth and final message back to Jenny." }
]

puts "\n🎯 Sending all messages rapidly (they should queue)..."

# Send all messages quickly without waiting
test_messages.each_with_index do |test, index|
  puts "  #{index + 1}. Sending #{test[:character]} message..."
  
  service = Services::CharacterService.new(character: test[:character])
  service.speak(test[:message])
end

puts "\n✅ All messages sent!"
puts "Listen for:"
puts "  - Each message playing in order"
puts "  - No interruptions or overlapping"
puts "  - Smooth transitions between voices"
puts "\nThe messages should take about 15-20 seconds total to play"
puts "=" * 60