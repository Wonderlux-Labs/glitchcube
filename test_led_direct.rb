#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'config/initializers/config'
require_relative 'lib/home_assistant_client'
require_relative 'lib/services/conversation_feedback_service'

puts '🔵 Direct LED test with debug output...'

# Test entity exists first
puts "\n1. Check entity exists:"
ha_client = HomeAssistantClient.new
begin
  state = ha_client.state('light.cube_voice_ring')
  puts "✅ Entity found: #{state['state']} - #{state.dig('attributes', 'friendly_name')}"
rescue StandardError => e
  puts "❌ Entity error: #{e.class} - #{e.message}"
  exit 1
end

puts "\n2. Test ConversationFeedbackService:"
result = Services::ConversationFeedbackService.set_listening
puts "Result: #{result}"

puts "\n3. Test direct HA call:"
begin
  result = ha_client.call_service('light', 'turn_on', {
                                    entity_id: 'light.cube_voice_ring',
                                    rgb_color: [0, 255, 0], # Green test
                                    brightness: 150
                                  })
  puts "✅ Direct call result: #{result.inspect}"
rescue StandardError => e
  puts "❌ Direct call error: #{e.class} - #{e.message}"
end
