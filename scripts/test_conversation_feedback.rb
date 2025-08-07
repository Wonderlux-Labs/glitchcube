#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for ConversationFeedbackService
# Demonstrates all conversation states with LED feedback

require_relative '../config/initializers/config'
require_relative '../lib/services/conversation_feedback_service'

puts "🎭 Testing Conversation Feedback LED States"
puts "=" * 50

feedback_service = Services::ConversationFeedbackService.new

# Test sequence simulating a full conversation
conversation_states = [
  { state: :idle, description: 'Ready and waiting for user', duration: 2 },
  { state: :listening, description: 'User is speaking to cube', duration: 3 },
  { state: :thinking, description: 'Processing user input', duration: 4 },
  { state: :speaking, description: 'Responding to user', duration: 5 },
  { state: :completed, description: 'Conversation finished', duration: 3 },
  { state: :idle, description: 'Back to ready state', duration: 2 }
]

puts "\n🔄 Running conversation state sequence..."

conversation_states.each_with_index do |state_config, index|
  state = state_config[:state]
  description = state_config[:description]
  duration = state_config[:duration]
  
  puts "\n#{index + 1}. #{state.to_s.upcase} - #{description}"
  
  begin
    # Set the LED state
    case state
    when :idle
      Services::ConversationFeedbackService.set_idle
    when :listening  
      Services::ConversationFeedbackService.set_listening
    when :thinking
      Services::ConversationFeedbackService.set_thinking
    when :speaking
      Services::ConversationFeedbackService.set_speaking
    when :completed
      Services::ConversationFeedbackService.set_completed
    end
    
    puts "   ✅ LED state set successfully"
    
    # Show current status
    status = feedback_service.get_status
    if status[:state] != 'unavailable'
      color = status[:rgb_color] || 'unknown'
      brightness = status[:brightness] || 'unknown'
      puts "   📊 Current: #{color} at #{brightness} brightness"
    else
      puts "   ⚠️  LED ring unavailable"
    end
    
  rescue => e
    puts "   ❌ Error: #{e.message}"
  end
  
  puts "   ⏱️  Waiting #{duration} seconds..."
  sleep(duration)
end

puts "\n🎨 Testing custom mood colors..."

mood_colors = [
  { color: '#FF69B4', brightness: 180, description: 'Hot Pink - Playful mood' },
  { color: '#32CD32', brightness: 150, description: 'Lime Green - Excited mood' },
  { color: '#9370DB', brightness: 120, description: 'Medium Purple - Mysterious mood' }
]

mood_colors.each do |mood|
  puts "\n🎨 #{mood[:description]}"
  
  begin
    Services::ConversationFeedbackService.set_mood_color(
      mood[:color], 
      brightness: mood[:brightness]
    )
    puts "   ✅ Mood color set: #{mood[:color]}"
  rescue => e
    puts "   ❌ Error: #{e.message}"
  end
  
  sleep(2)
end

puts "\n🧪 Testing error state..."

begin
  Services::ConversationFeedbackService.set_error
  puts "   ✅ Error state set (flashing red)"
  sleep(3)
rescue => e
  puts "   ❌ Error setting error state: #{e.message}"
end

puts "\n🔄 Returning to idle state..."
begin
  Services::ConversationFeedbackService.set_idle
  puts "   ✅ Back to idle (dim ready state)"
rescue => e
  puts "   ❌ Error: #{e.message}"
end

puts "\n" + "=" * 50
puts "🎭 Conversation Feedback Test Complete!"
puts ""
puts "💡 Next steps:"
puts "   1. Rename LED entity in Home Assistant to 'cube_speaker_light'"
puts "   2. Test with actual conversation flow"
puts "   3. Adjust colors/timing based on user experience"