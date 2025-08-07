#!/usr/bin/env ruby
# frozen_string_literal: true

# Test Home Assistant connection and list entities
require 'bundler/setup'
require_relative '../app'

puts "Testing Home Assistant connection..."
puts "URL: #{GlitchCube.config.home_assistant.url || 'Not configured'}"
puts "Token: #{GlitchCube.config.home_assistant.token ? '***' + GlitchCube.config.home_assistant.token[-8..] : 'Not configured'}"
puts "Mock enabled: #{GlitchCube.config.home_assistant.mock_enabled}"

if GlitchCube.config.home_assistant.mock_enabled
  puts "\n⚠️  Mock mode is enabled. Set MOCK_HOME_ASSISTANT=false to connect to real HA"
  exit 0
end

client = HomeAssistantClient.new

begin
  puts "\n📡 Attempting to connect..."
  states = client.states
  
  if states.nil?
    puts "❌ Failed to get states - response was nil"
  elsif states.empty?
    puts "⚠️  Connected but no entities found"
  else
    puts "✅ Connected successfully!"
    puts "Found #{states.count} entities"
    
    # Group by domain
    domains = {}
    states.each do |state|
      domain = state['entity_id'].split('.').first
      domains[domain] ||= 0
      domains[domain] += 1
    end
    
    puts "\nEntity domains:"
    domains.sort.each do |domain, count|
      puts "  #{domain}: #{count}"
    end
    
    # Look for weather entities
    weather_entities = states.select { |s| s['entity_id'].include?('weather') }
    if weather_entities.any?
      puts "\n🌤️  Weather entities found:"
      weather_entities.each do |entity|
        puts "  - #{entity['entity_id']}: #{entity['state']}"
      end
    end
    
    # Look for camera entities
    camera_entities = states.select { |s| s['entity_id'].start_with?('camera.') }
    if camera_entities.any?
      puts "\n📷 Camera entities found:"
      camera_entities.each do |entity|
        puts "  - #{entity['entity_id']}: #{entity['state']}"
      end
    end
  end
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts "\nTroubleshooting:"
  puts "1. Check if Home Assistant is running"
  puts "2. Verify the URL is correct (current: #{GlitchCube.config.home_assistant.url})"
  puts "3. Check if the token is valid"
  puts "4. Try accessing: #{GlitchCube.config.home_assistant.url}/api/"
end