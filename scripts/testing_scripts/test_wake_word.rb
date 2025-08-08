#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to trigger wake word detection programmatically
# This simulates what happens when someone says "Hey Glitch Cube"

require 'bundler/setup'
require_relative 'config/environment'
require_relative 'config/initializers/config'
require_relative 'lib/home_assistant_client'
require 'json'

puts "🎤 Wake Word Detection Test"
puts "=" * 50

client = HomeAssistantClient.new

# Test different conversation triggers
tests = [
  {
    name: "Basic Wake Word",
    service_call: -> {
      client.call_service(
        'conversation',
        'process',
        {
          text: 'Hello, are you listening?',
          agent_id: 'conversation.glitchcube',
          language: 'en'
        }
      )
    }
  },
  {
    name: "Multi-turn Conversation",
    service_call: -> {
      # First turn
      result1 = client.call_service(
        'conversation',
        'process',
        {
          text: 'Hey Glitch Cube, what is your purpose?',
          agent_id: 'conversation.glitchcube',
          language: 'en'
        }
      )
      
      puts "  First response: #{result1['response']['speech']['plain']['speech'] rescue result1}"
      
      # Continue conversation
      if result1 && result1['conversation_id']
        sleep 2 # Give time for TTS to complete
        
        client.call_service(
          'conversation',
          'process',
          {
            text: 'Tell me more about that',
            agent_id: 'conversation.glitchcube',
            conversation_id: result1['conversation_id'],
            language: 'en'
          }
        )
      else
        result1
      end
    }
  },
  {
    name: "Assist Pipeline (Modern HA)",
    service_call: -> {
      client.call_service(
        'assist_pipeline',
        'start',
        {
          start_stage: 'intent',
          end_stage: 'tts',
          input: {
            text: 'What can you do?'
          },
          conversation_id: SecureRandom.uuid,
          device_id: 'test_wake_word_script'
        },
        return_response: true
      )
    }
  },
  {
    name: "Event-based Trigger (Automation Style)",
    service_call: -> {
      # Fire an event that could trigger an automation
      client.call_service(
        'event',
        'fire',
        {
          event_type: 'wake_word_detected',
          event_data: {
            text: 'Testing wake word detection',
            source: 'test_script',
            timestamp: Time.now.iso8601
          }
        }
      )
    }
  }
]

# Run tests
tests.each_with_index do |test, index|
  puts "\n#{index + 1}. Testing: #{test[:name]}"
  puts "-" * 40
  
  begin
    result = test[:service_call].call
    
    if result
      # Try to extract the response text
      response_text = case result
      when Hash
        if result['response'] && result['response']['speech']
          result['response']['speech']['plain']['speech']
        elsif result['pipeline_run'] && result['pipeline_run']['tts']
          result['pipeline_run']['tts']['tts_output']
        elsif result['data'] && result['data']['response']
          result['data']['response']
        else
          result.to_json
        end
      else
        result.to_s
      end
      
      puts "✅ Success!"
      puts "Response: #{response_text}" if response_text
    else
      puts "⚠️  No response received"
    end
    
  rescue => e
    puts "❌ Error: #{e.message}"
    puts e.backtrace.first(3).join("\n") if ENV['DEBUG']
  end
  
  sleep 1 # Brief pause between tests
end

puts "\n" + "=" * 50
puts "🎤 Wake Word Detection Test Complete"

# Show how to use in Home Assistant automation
puts "\n📝 Example Home Assistant Automation:"
automation_yaml = <<~YAML
  alias: "Glitch Cube Wake Word Response"
  trigger:
    - platform: conversation
      command: 
        - "Hey Glitch Cube"
        - "OK Glitch Cube"
  action:
    - service: conversation.process
      data:
        text: "{{ trigger.sentence }}"
        agent_id: conversation.glitchcube
        language: en
YAML

puts automation_yaml