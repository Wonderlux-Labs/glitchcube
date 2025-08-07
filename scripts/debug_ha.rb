#!/usr/bin/env ruby
# frozen_string_literal: true

puts '🏠 Debug Home Assistant connection...'

begin
  ha_client = HomeAssistantClient.new
  puts '✅ HomeAssistantClient created successfully'
  puts "📡 URL: #{ha_client.base_url}"
  puts "🔑 Token: #{ha_client.token ? 'configured' : 'missing'}"

  puts "\n🔍 Testing states call..."
  states = ha_client.states
  puts "📊 Got #{states.size} entities"

  puts "\n💡 Testing LED entity specifically..."
  led_state = ha_client.state('light.home_assistant_voice_09739d_led_ring')
  puts "LED state: #{led_state}"
rescue StandardError => e
  puts "❌ Error: #{e.class} - #{e.message}"
  puts 'Backtrace:'
  puts e.backtrace.first(5)
end
