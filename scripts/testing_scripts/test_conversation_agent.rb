#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to check conversation agent configuration

require 'bundler/setup'

require 'json'

puts '🔍 Checking Conversation Agent Configuration'
puts '=' * 50

client = HomeAssistantClient.new

# Test 1: Check states to verify HA connection
puts "\n1. Checking Home Assistant connection..."
begin
  # Use public states method
  states = client.states

  if states.is_a?(Array)
    puts "✅ Connected to Home Assistant (#{states.size} entities)"
    # Look for conversation-related entities
    conversation_entities = states.select { |s| s['entity_id'].include?('conversation') }
    if conversation_entities.any?
      puts '   Found conversation entities:'
      conversation_entities.each { |e| puts "   - #{e['entity_id']}" }
    end
  else
    puts '⚠️  No states returned'
  end
rescue StandardError => e
  puts "❌ Error checking states: #{e.message}"
end

# Test 2: Check configured conversation agents
puts "\n2. Checking conversation agents..."
begin
  # Try to get conversation agent info
  # Note: This endpoint might not exist in all HA versions
  agents = client.get('/api/config/conversation')

  if agents
    puts '✅ Conversation config found:'
    puts JSON.pretty_generate(agents)
  end
rescue StandardError => e
  puts "⚠️  Could not get conversation config: #{e.message}"
end

# Test 3: Check if our custom component is loaded
puts "\n3. Checking custom components..."
begin
  # Get loaded components
  components = client.get('/api/config')

  if components && components['components']
    if components['components'].include?('glitchcube_conversation')
      puts '✅ glitchcube_conversation component is loaded'
    else
      puts '⚠️  glitchcube_conversation component not found in loaded components'
      puts '   Loaded conversation-related components:'
      components['components'].select { |c| c.include?('conversation') }.each do |comp|
        puts "   - #{comp}"
      end
    end
  end
rescue StandardError => e
  puts "❌ Error checking components: #{e.message}"
end

# Test 4: Try a simple conversation process with default agent
puts "\n4. Testing default conversation agent..."
begin
  # Try without specifying agent_id to use default
  result = client.call_service(
    'conversation',
    'process',
    {
      text: 'Hello'
    }
  )

  if result
    puts '✅ Default conversation agent responded'
    puts "   Response type: #{result.class}"
    puts "   Keys: #{result.keys.join(', ')}" if result.is_a?(Hash)
  end
rescue StandardError => e
  puts "❌ Error with default agent: #{e.message}"
end

# Test 5: Check assist_pipeline configuration
puts "\n5. Checking assist_pipeline..."
begin
  # Check if assist_pipeline service exists
  services = client.get('/api/services')

  if services.is_a?(Array)
    assist_services = services.find { |s| s['domain'] == 'assist_pipeline' }
    if assist_services
      puts '✅ Assist pipeline domain found with services:'
      assist_services['services'].each_key do |service_name|
        puts "   - #{service_name}"
      end
    else
      puts '⚠️  Assist pipeline domain not found (might be using older HA version)'
    end
  end
rescue StandardError => e
  puts "❌ Error checking assist_pipeline: #{e.message}"
end

# Test 6: Direct webhook test
puts "\n6. Testing webhook endpoint..."
begin
  webhook_service = Services::HomeAssistantWebhookService.new

  result = webhook_service.send_update({
                                         test: 'wake_word_test',
                                         timestamp: Time.now.iso8601
                                       })

  if result[:success]
    puts '✅ Webhook endpoint is accessible'
  else
    puts "⚠️  Webhook returned: #{result[:error]}"
  end
rescue StandardError => e
  puts "❌ Error testing webhook: #{e.message}"
end

puts "\n#{'=' * 50}"
puts '🔍 Configuration Check Complete'

# Show recommendations
puts "\n📝 Recommendations:"
puts '1. Ensure glitchcube_conversation is in /config/custom_components/'
puts '2. Check Home Assistant logs for component loading errors'
puts "3. Verify the agent_id format (might need 'agent.' prefix)"
puts '4. Consider using webhook endpoint as fallback'
