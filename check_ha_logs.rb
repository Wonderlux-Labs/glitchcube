#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to check Home Assistant logs for errors

require 'bundler/setup'
require_relative 'config/environment'
require_relative 'config/initializers/config'
require_relative 'lib/home_assistant_client'
require 'json'
require 'time'

puts "📋 Checking Home Assistant Logs"
puts "=" * 50

client = HomeAssistantClient.new

# Check system log via logbook API
puts "\n1. Recent Logbook Entries:"
begin
  # Get logbook entries for the last hour
  end_time = Time.now.iso8601
  start_time = (Time.now - 3600).iso8601  # 1 hour ago
  
  # Use call_service to get logbook entries
  result = client.call_service(
    'logbook',
    'log',
    {
      name: 'Conversation Test',
      message: 'Checking logs for conversation errors',
      entity_id: 'sensor.glitchcube_api_health',
      domain: 'conversation'
    }
  )
  
  puts "✅ Logged test entry"
rescue => e
  puts "⚠️  Could not write to logbook: #{e.message}"
end

# Check system health
puts "\n2. System Health Check:"
begin
  # Get the health sensor state
  health_state = client.state('sensor.glitchcube_api_health')
  if health_state
    puts "   API Health: #{health_state['state']}"
    if health_state['attributes']
      puts "   Last check: #{health_state['attributes']['last_check']}"
      puts "   Error count: #{health_state['attributes']['error_count']}" if health_state['attributes']['error_count']
    end
  end
rescue => e
  puts "❌ Error checking health: #{e.message}"
end

# Check for error sensors
puts "\n3. Error-related Sensors:"
begin
  states = client.states
  error_entities = states.select do |s| 
    s['entity_id'].include?('error') || 
    s['entity_id'].include?('warning') ||
    s['entity_id'].include?('alert')
  end
  
  if error_entities.any?
    error_entities.each do |entity|
      puts "   #{entity['entity_id']}: #{entity['state']}"
    end
  else
    puts "   No error entities found"
  end
rescue => e
  puts "❌ Error checking sensors: #{e.message}"
end

# Try to trigger a conversation and capture the actual error
puts "\n4. Testing Conversation with Error Details:"
begin
  # First, try without agent_id to see what happens
  puts "   Testing without agent_id..."
  result = client.call_service(
    'conversation',
    'process',
    {
      text: 'Test message for error checking'
    }
  )
  puts "   ✅ Success without agent_id: #{result.class}"
  
  # Now try with our custom agent
  puts "\n   Testing with agent_id='conversation.glitchcube'..."
  result = client.call_service(
    'conversation',
    'process',
    {
      text: 'Test message for custom agent',
      agent_id: 'conversation.glitchcube'
    }
  )
  puts "   ✅ Success with custom agent"
  
rescue => e
  puts "   ❌ Error: #{e.message}"
  
  # Try alternative agent ID formats
  puts "\n   Trying alternative formats..."
  
  ['glitchcube', 'agent.glitchcube', 'glitchcube_conversation'].each do |agent_id|
    begin
      puts "   Testing agent_id='#{agent_id}'..."
      result = client.call_service(
        'conversation',
        'process',
        {
          text: 'Test',
          agent_id: agent_id
        }
      )
      puts "   ✅ Success with '#{agent_id}'"
      break
    rescue => e
      puts "   ❌ Failed: #{e.message.split("\n").first}"
    end
  end
end

# Check if we can access error logs via REST sensor
puts "\n5. Checking for Log Sensors:"
begin
  log_sensors = client.states.select { |s| s['entity_id'].include?('log') }
  
  if log_sensors.any?
    puts "   Found log sensors:"
    log_sensors.each do |sensor|
      puts "   - #{sensor['entity_id']}"
      if sensor['state'] && sensor['state'].length > 0 && sensor['state'] != 'unknown'
        puts "     State: #{sensor['state'][0..100]}..." 
      end
    end
  else
    puts "   No log sensors found"
  end
rescue => e
  puts "❌ Error checking log sensors: #{e.message}"
end

puts "\n" + "=" * 50
puts "📋 Log Check Complete"

puts "\n💡 To get detailed logs, you may need to:"
puts "1. SSH into Home Assistant: ssh user@glitch.local"
puts "2. Check logs: docker logs homeassistant 2>&1 | grep -i conversation"
puts "3. Or check the UI: Configuration -> Logs"
puts "4. Enable debug logging for conversation component in configuration.yaml:"
puts <<~YAML
  
  logger:
    default: info
    logs:
      homeassistant.components.conversation: debug
      custom_components.glitchcube_conversation: debug
YAML