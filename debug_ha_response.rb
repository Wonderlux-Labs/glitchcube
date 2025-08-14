#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'config/environment'

# Test the HA API call directly to see what we get back
def test_ha_conversation_api
  puts '🔍 Testing Home Assistant Conversation API directly'
  puts '=' * 60

  ha_client = Core::HomeAssistantClient.new

  formatted_request = "Please execute these tools and report the results:\n1. Turn on light.living_room\n2. Say \"The lights are now on\" in Josh voice"

  puts '📤 Sending request to HA Claude conversation agent:'
  puts formatted_request

  begin
    response = ha_client.process_voice_command(
      text: formatted_request,
      agent_id: 'conversation.claude_conversation',
      conversation_id: 'debug-test-session',
      return_response: true
    )

    puts "\n✅ SUCCESS - HA Response received:"
    puts "Response class: #{response.class}"
    puts "Response inspect: #{response.inspect}"
    puts "Response keys: #{response.keys}" if response.is_a?(Hash)

    if response.is_a?(Hash) && response['response']
      puts "\nNested response:"
      puts response['response'].inspect
    end
  rescue StandardError => e
    puts "\n❌ ERROR calling HA conversation API:"
    puts "Error class: #{e.class}"
    puts "Error message: #{e.message}"
    puts "Error backtrace: #{e.backtrace[0..5].join("\n")}"
  end
end

if __FILE__ == $0
  test_ha_conversation_api
end
