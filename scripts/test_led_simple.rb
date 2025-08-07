#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple LED test
puts "🔵 Testing LED: Setting to listening state..."
result = Services::ConversationFeedbackService.set_listening
puts "Result: #{result}"

puts "🟠 Testing LED: Setting to thinking state..."  
result = Services::ConversationFeedbackService.set_thinking
puts "Result: #{result}"

puts "🟢 Testing LED: Setting to speaking state..."
result = Services::ConversationFeedbackService.set_speaking  
puts "Result: #{result}"

puts "🟣 Testing LED: Setting to completed state..."
result = Services::ConversationFeedbackService.set_completed
puts "Result: #{result}"

puts "✅ LED tests complete!"