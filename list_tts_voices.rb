#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to list available TTS voices from Home Assistant

require 'bundler/setup'
require 'dotenv'
require 'net/http'
require 'json'

Dotenv.load

# Load the app and dependencies
require_relative 'app'

puts '=' * 50
puts 'TTS Voice Information'
puts '=' * 50

client = HomeAssistantClient.new

# Try to get TTS provider info
begin
  # Get all states
  states = client.states

  # Find TTS entities
  tts_entities = states.select { |s| s['entity_id'].start_with?('tts.') }

  puts "\n📢 Available TTS entities:"
  tts_entities.each do |entity|
    puts "\n  #{entity['entity_id']}:"
    puts "    State: #{entity['state']}"

    next unless entity['attributes']

    entity['attributes'].each do |key, value|
      if value.is_a?(Array) && key == 'supported_languages'
        puts "    #{key}: #{value.length} languages"
      elsif value.is_a?(Array) && key == 'voices'
        puts "    #{key}: #{value.length} voices available"
        # Show first few as examples
        if value.length.positive?
          puts "      Examples: #{value.first(5).join(', ')}#{'...' if value.length > 5}"
        end
      else
        puts "    #{key}: #{value}"
      end
    end
  end

  # Try to get service info
  puts "\n#{'=' * 50}"
  puts 'TTS Service Information'
  puts '=' * 50

  # Make a call to get services list if available
  begin
    services_response = client.get('/api/services')
    if services_response.is_a?(Array)
      tts_services = services_response.select { |s| s['domain'] == 'tts' }

      if tts_services.any?
        puts "\n📣 Available TTS services:"
        tts_services.first['services'].each do |service_name, service_info|
          puts "\n  tts.#{service_name}:"
          puts "    Description: #{service_info['description']}" if service_info['description']
          next unless service_info['fields']

          puts '    Parameters:'
          service_info['fields'].each do |field_name, field_info|
            puts "      - #{field_name}: #{field_info['description'] || field_info['example']}"
          end
        end
      end
    end
  rescue StandardError => e
    puts "Could not fetch service information: #{e.message}"
  end
rescue StandardError => e
  puts "Error fetching TTS info: #{e.message}"
end

puts "\n💡 To see what voices actually work differently, try testing a few specific ones with different messages."
puts '   The API seems to accept any voice name but may fall back to default for unsupported variants.'
puts "\n✨ Done!"
