#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for persona Home Assistant synchronization
# Usage: ruby scripts/test_persona_ha_sync.rb [persona_name]

require_relative '../config/boot'

persona = ARGV[0] || 'buddy'

puts '🎭 Testing persona sync with Home Assistant'
puts '=' * 50

# Set the persona
puts "\n📝 Setting persona to: #{persona}"
begin
  Services::PersonaStateService.set_current_persona(persona)
  puts '✅ Persona set successfully in Redis'
rescue StandardError => e
  puts "❌ Error setting persona: #{e.message}"
  exit 1
end

# Check what got stored in Redis
current = Services::PersonaStateService.get_current_persona
puts "\n🔍 Current persona in Redis: #{current}"

# Check Home Assistant state
puts "\n🏠 Checking Home Assistant state..."
begin
  ha_client = HomeAssistantClient.new
  ha_state = ha_client.state('input_text.current_persona')

  if ha_state && ha_state['state']
    puts "✅ Home Assistant state: #{ha_state['state']}"
    puts '   Attributes:'
    ha_state['attributes']&.each do |key, value|
      puts "   - #{key}: #{value}"
    end
  else
    puts '❌ Could not read Home Assistant state'
  end
rescue StandardError => e
  puts "❌ Error reading HA state: #{e.message}"
end

# Test setting each persona
puts "\n🔄 Testing all personas..."
%w[buddy jax lomi zorp].each do |p|
  print "   Setting #{p}... "
  Services::PersonaStateService.set_current_persona(p)
  sleep 0.5
  ha_state = HomeAssistantClient.new.state('input_text.current_persona')
  if ha_state && ha_state['state'] == p
    puts '✅'
  else
    puts "❌ (expected #{p}, got #{ha_state&.dig('state')})"
  end
end

puts "\n✨ Test complete!"
puts "\nYou can now create a Home Assistant automation that triggers when"
puts 'input_text.current_persona changes to switch the voice assistant!'
puts "\nExample automation trigger:"
puts '  trigger:'
puts '    - platform: state'
puts '      entity_id: input_text.current_persona'
puts "\nThen in the action, you can use the new value:"
puts "  {{ states('input_text.current_persona') }}"
