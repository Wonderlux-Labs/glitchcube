#!/usr/bin/env ruby
# frozen_string_literal: true

# Test LED with new entity name and debug output
puts '🔵 Testing LED with new entity name: cube_voice_light'

# Test the service
puts "\n1. Testing ConversationFeedbackService.set_listening..."
result = Services::ConversationFeedbackService.set_listening
puts "Result: #{result}"

sleep(2)

puts "\n2. Testing ConversationFeedbackService.set_thinking..."
result = Services::ConversationFeedbackService.set_thinking
puts "Result: #{result}"

sleep(2)

puts "\n3. Testing direct HA call with new entity..."
begin
  ha_client = HomeAssistantClient.new
  result = ha_client.call_service('light', 'turn_on', {
                                    entity_id: 'light.cube_voice_light',
                                    rgb_color: [255, 0, 255], # Magenta test
                                    brightness: 200,
                                    transition: 0.5
                                  })
  puts "✅ Direct HA result: #{result.inspect}"
rescue StandardError => e
  puts "❌ Direct HA error: #{e.class} - #{e.message}"
end

puts "\n✅ LED debug test complete!"
