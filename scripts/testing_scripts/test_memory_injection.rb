#!/usr/bin/env ruby
# Test memory injection in conversations

require_relative 'config/environment'
require_relative 'app'

puts "=== Testing Memory Injection in Conversations ==="

# Enable debug mode to see memory injection
GlitchCube.config.instance_eval { @debug = true }

# Test conversation with memory injection
puts "\n🎭 Testing conversation with location context (should inject memories):"
conversation = ConversationModule.new(persona: 'buddy')

response = conversation.call(
  message: "Hey, what's happening around here?",
  context: {
    location: "Center Camp",
    include_sensors: false,
    skip_memories: false  # Explicitly enable memories
  }
)

puts "\nResponse: #{response[:response][0..200]}..."
puts "Persona: #{response[:persona]}"

# Test without memory injection
puts "\n🚫 Testing conversation WITHOUT memory injection:"
response2 = conversation.call(
  message: "Tell me a story",
  context: {
    skip_memories: true  # Explicitly disable memories
  }
)

puts "\nResponse: #{response2[:response][0..200]}..."

# Check memory recall counts
puts "\n📊 Memory recall counts after conversations:"
Memory.all.each do |m|
  puts "  Memory ##{m.id}: recalled #{m.recall_count} times - #{m.content[0..50]}..."
end

puts "\n✨ Memory injection test complete!"