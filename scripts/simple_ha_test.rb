#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

# Read configuration from .env
require 'dotenv'
Dotenv.load

url = ENV['HOME_ASSISTANT_URL'] || 'http://glitchcube.local:8123'
token = ENV['HOME_ASSISTANT_TOKEN']

if token.nil? || token == 'changeme-ha-token'
  puts "❌ HOME_ASSISTANT_TOKEN not configured in .env"
  exit 1
end

puts "Testing Home Assistant connection..."
puts "URL: #{url}"
puts "Token: ***#{token[-8..]}"

begin
  uri = URI.parse("#{url}/api/states")
  http = Net::HTTP.new(uri.host, uri.port)
  http.read_timeout = 5
  
  request = Net::HTTP::Get.new(uri.request_uri)
  request['Authorization'] = "Bearer #{token}"
  request['Content-Type'] = 'application/json'
  
  response = http.request(request)
  
  if response.code == '200'
    states = JSON.parse(response.body)
    puts "✅ Connected successfully!"
    puts "Found #{states.count} entities"
    
    # Save raw response for debugging
    File.write('tmp/ha_entities.json', JSON.pretty_generate(states))
    puts "Raw data saved to tmp/ha_entities.json"
    
    # Group by domain
    domains = {}
    states.each do |state|
      domain = state['entity_id'].split('.').first
      domains[domain] ||= []
      domains[domain] << state['entity_id']
    end
    
    puts "\nEntity domains:"
    domains.sort.each do |domain, entities|
      puts "  #{domain}: #{entities.count}"
    end
    
    # Look for key entities
    important_entities = {
      'weather' => states.select { |s| s['entity_id'].include?('weather') },
      'camera' => states.select { |s| s['entity_id'].start_with?('camera.') },
      'sensor.playa_weather' => states.select { |s| s['entity_id'].include?('playa_weather') },
      'input_text' => states.select { |s| s['entity_id'].start_with?('input_text.') }
    }
    
    important_entities.each do |category, entities|
      if entities.any?
        puts "\n#{category}:"
        entities.first(5).each do |entity|
          puts "  - #{entity['entity_id']}: #{entity['state'][0..50]}"
        end
      end
    end
  else
    puts "❌ Failed with status #{response.code}: #{response.message}"
    puts "Response: #{response.body[0..200]}"
  end
rescue => e
  puts "❌ Error: #{e.message}"
  puts "Make sure Home Assistant is running at #{url}"
end