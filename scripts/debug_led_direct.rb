#!/usr/bin/env ruby
# frozen_string_literal: true

puts '🔵 Testing direct LED control...'

ha_client = HomeAssistantClient.new

# Try direct Home Assistant call first
puts "\n1. Direct HA call test:"
begin
  result = ha_client.call_service('light', 'turn_on', {
                                    entity_id: 'light.home_assistant_voice_09739d_led_ring',
                                    rgb_color: [0, 128, 255], # Blue
                                    brightness: 200,
                                    transition: 0.5
                                  })
  puts "✅ Direct call result: #{result}"
rescue StandardError => e
  puts "❌ Direct call error: #{e.message}"
end

sleep(2)

# Now test through our service
puts "\n2. ConversationFeedbackService test:"
begin
  service = Services::ConversationFeedbackService.new
  result = service.set_state(:listening)
  puts "Service result: #{result}"
rescue StandardError => e
  puts "❌ Service error: #{e.class} - #{e.message}"
  puts e.backtrace.first(3)
end

sleep(2)

# Test class method
puts "\n3. Class method test:"
begin
  result = Services::ConversationFeedbackService.set_thinking
  puts "Class method result: #{result}"
rescue StandardError => e
  puts "❌ Class method error: #{e.class} - #{e.message}"
end
