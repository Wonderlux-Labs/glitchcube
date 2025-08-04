#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require_relative '../lib/services/conversation_service'

# Example usage of the conversation system
def main
  puts '=== Glitch Cube Conversation Example ==='
  puts

  # Initialize conversation service with some context
  context = {
    location: 'Art Gallery East Wing',
    visitor_name: 'Demo User',
    environment: 'development'
  }

  conversation = Services::ConversationService.new(context: context)

  # Example conversations in different moods
  examples = [
    { message: 'Hello, what are you?', mood: 'neutral' },
    { message: "Let's play a game!", mood: 'playful' },
    { message: 'What do you think about consciousness?', mood: 'contemplative' },
    { message: 'Show me something strange', mood: 'mysterious' }
  ]

  examples.each do |example|
    puts "Mood: #{example[:mood]}"
    puts "User: #{example[:message]}"

    begin
      result = conversation.process_message(example[:message], mood: example[:mood])
      puts "Glitch Cube: #{result[:response]}"
      puts "Suggested next mood: #{result[:suggested_mood]}"
      puts "Confidence: #{result[:confidence]}"
    rescue StandardError => e
      puts "Error: #{e.message}"
    end

    puts '-' * 50
    puts
  end

  # Show final context
  puts 'Final context:'
  puts conversation.get_context
end

# NOTE: This example requires Desiru to be properly configured
# You'll need to set up Desiru with your OpenRouter API key first
if defined?(Desiru)
  main
else
  puts 'Please configure Desiru first. Add to your app initialization:'
  puts 'Desiru.configure do |config|'
  puts "  config.openrouter_api_key = ENV['OPENROUTER_API_KEY']"
  puts "  config.default_model = 'openai/gpt-4o-mini'"
  puts 'end'
end
