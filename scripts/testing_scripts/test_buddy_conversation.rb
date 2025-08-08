#!/usr/bin/env ruby

# Quick test script to verify BUDDY persona with tools
require_relative 'lib/modules/conversation_module'

puts "🤖 Testing BUDDY conversation with tools..."
puts "=" * 50

# Create conversation module
conv = ConversationModule.new

# Test with BUDDY persona - should auto-load his tools
context = {
  session_id: "test_buddy_#{Time.now.to_i}",
  source: 'test_script',
  persona: 'buddy'
}

# Test message that should trigger tools
message = "Hey BUDDY! Can you turn the lights blue and play some music?"

puts "💬 User: #{message}"
puts "\n🔄 Processing with BUDDY persona..."
puts "   Expected tools: error_handling, test_tool, lighting_control, music_control, home_assistant, display_control"

begin
  result = conv.call(
    message: message,
    context: context,
    persona: 'buddy'
  )
  
  puts "\n✅ Response received:"
  puts "   Persona: #{result[:persona]}"
  puts "   Model: #{result[:model]}"
  puts "   Cost: $#{result[:cost]}" if result[:cost]
  puts "   Response: #{result[:response]}"
  puts "   Error: #{result[:error]}" if result[:error]
  
rescue => e
  puts "\n❌ Error occurred:"
  puts "   #{e.class}: #{e.message}"
  puts "   #{e.backtrace.first(3).join("\n   ")}" if e.backtrace
end

puts "\n" + "=" * 50
puts "🎯 Test complete!"