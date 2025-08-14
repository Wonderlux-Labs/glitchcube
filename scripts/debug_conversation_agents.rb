#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../config/environment'

def main
  puts '🔍 Debugging Home Assistant Conversation Agents'
  puts '=' * 60

  ha_client = Core::HomeAssistantClient.new

  # Get all entities
  puts "\n1. Getting all conversation entities..."
  begin
    states = ha_client.states
    conversation_entities = states.select { |entity| entity['entity_id'].start_with?('conversation.') }

    if conversation_entities.any?
      puts "Found #{conversation_entities.count} conversation entities:"
      conversation_entities.each do |entity|
        puts "  - #{entity['entity_id']}: #{entity['state']} (#{entity.dig('attributes', 'friendly_name')})"
      end
    else
      puts '  No conversation entities found'
    end
  rescue StandardError => e
    puts "  ERROR getting states: #{e.message}"
  end

  # Test basic conversation
  puts "\n2. Testing basic conversation (no agent_id)..."
  begin
    response = ha_client.process_voice_command(
      'What conversation agents are available?',
      return_response: true
    )
    puts "  Response: #{response['response']['speech']['plain']['speech']}" if response.dig('response', 'speech', 'plain', 'speech')
    puts "  Full response: #{response.inspect}"
  rescue StandardError => e
    puts "  ERROR: #{e.message}"
  end

  # Test with different agent_id values
  potential_agents = [
    'conversation.home_assistant',
    'conversation.chatgpt',
    'conversation.claude_background',
    'conversation.openai'
  ]

  puts "\n3. Testing different agent_id values..."
  potential_agents.each do |agent_id|
    puts "\n  Testing agent: #{agent_id}"
    begin
      response = ha_client.process_voice_command(
        'Hello, what is your name?',
        agent_id: agent_id,
        return_response: true
      )
      puts "    SUCCESS: #{response['response']['speech']['plain']['speech']}" if response.dig('response', 'speech', 'plain', 'speech')
    rescue StandardError => e
      puts "    ERROR: #{e.message}"
    end
  end

  # Try the conversation_engine approach from your research
  puts "\n4. Testing conversation_engine approach..."
  begin
    # This might not work with the Ruby client but worth documenting
    response = ha_client.call_service('conversation', 'process', {
                                        text: 'Hello, can you execute tools?',
                                        conversation_engine: 'conversation.chatgpt'
                                      }, return_response: true)
    puts "  SUCCESS with conversation_engine: #{response.inspect}"
  rescue StandardError => e
    puts "  ERROR with conversation_engine: #{e.message}"
  end

  puts "\n#{'=' * 60}"
  puts 'Debug complete! Check results above.'
end

if __FILE__ == $0
  main
end
