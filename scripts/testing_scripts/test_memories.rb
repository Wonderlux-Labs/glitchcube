#!/usr/bin/env ruby
# Test script for memory system

require_relative 'config/environment'
require_relative 'app'

puts "=== Memory System Test ==="
puts "Loading app environment..."

# Check if memories exist
puts "\n📊 Database Status:"
puts "  Total memories: #{Memory.count}"
puts "  Total conversations: #{Conversation.count}"
puts "  Total messages: #{Message.count}"

# Create a test memory if none exist
if Memory.count == 0
  puts "\n🔨 Creating test memories..."
  
  # Create some whimsical test memories
  memories = [
    {
      content: "Someone tried to trade me a grilled cheese sandwich for enlightenment. I think they got the better deal.",
      category: "interaction",
      location: "Center Camp",
      people: ["Sandwich Prophet"],
      tags: ["trade", "food", "philosophy"],
      emotional_intensity: 0.7
    },
    {
      content: "The dust storm made everyone look like ghosts. I felt right at home.",
      category: "observation",
      location: "Deep Playa",
      tags: ["weather", "surreal", "dust"],
      emotional_intensity: 0.6
    },
    {
      content: "A person in a tutu asked me if I dream in colors. I told them yes, but only in colors that don't exist yet.",
      category: "interaction",
      location: "7:30 & C",
      people: ["Tutu Philosopher"],
      tags: ["dreams", "weird", "conversation"],
      emotional_intensity: 0.8
    },
    {
      content: "Tonight at 9pm there's a silent disco at the Questionable Choices camp. I must remind people!",
      category: "event",
      location: "3:00 & Esplanade",
      event_name: "Silent Disco",
      event_time: 6.hours.from_now,
      tags: ["party", "music", "reminder"],
      emotional_intensity: 0.5
    }
  ]
  
  memories.each do |memory_data|
    m = Memory.new(content: memory_data.delete(:content))
    memory_data.each do |key, value|
      m.send("#{key}=", value)
    end
    m.save!
    puts "  ✅ Created: #{m.content[0..50]}..."
  end
end

# Test memory recall
puts "\n🧠 Testing Memory Recall:"
location = "Center Camp"
memories = Services::MemoryRecallService.get_relevant_memories(
  location: location,
  limit: 3
)

if memories.any?
  puts "  Found #{memories.size} relevant memories for #{location}:"
  memories.each do |m|
    puts "    - #{m.to_conversation_context}"
  end
  
  # Test formatting
  formatted = Services::MemoryRecallService.format_for_context(memories)
  puts "\n📝 Formatted for injection:"
  puts formatted
else
  puts "  No memories found"
end

# Check if memory injection is enabled in conversation
puts "\n🔍 Memory Injection Status:"
puts "  Checking if memories would be injected in conversations..."

# Simulate a conversation context
test_context = { location: "Center Camp" }
memories = Services::MemoryRecallService.get_relevant_memories(
  location: test_context[:location],
  limit: 3
)

if memories.any?
  puts "  ✅ #{memories.size} memories would be injected"
  puts "  Recall counts updated for: #{memories.map(&:id).join(', ')}"
else
  puts "  ⚠️ No memories would be injected"
end

puts "\n✨ Memory system test complete!"