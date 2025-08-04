#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick test script for Home Assistant API

require 'dotenv/load'
require 'httparty'
require 'json'

# Load config from .env
ha_url = ENV['HA_URL'] || 'localhost:8123'
ha_token = ENV.fetch('HOME_ASSISTANT_TOKEN', nil)

puts '🏠 Testing Home Assistant API'
puts "URL: http://#{ha_url}"
puts "Token: #{ha_token ? "#{ha_token[0..10]}..." : 'NOT SET'}"
puts '=' * 40

# Test basic connection
puts "\n1. Testing basic API connection..."
begin
  response = HTTParty.get("http://#{ha_url}/api/",
                          headers: {
                            'Authorization' => "Bearer #{ha_token}",
                            'Content-Type' => 'application/json'
                          },
                          timeout: 10)

  puts "Status: #{response.code}"
  puts "Response: #{response.body[0..200]}..."

  if response.code == 200
    puts '✅ Basic API connection successful!'
  else
    puts '❌ API connection failed'
  end
rescue StandardError => e
  puts "❌ Connection error: #{e.message}"
end

# Test getting states
puts "\n2. Testing states endpoint..."
begin
  response = HTTParty.get("http://#{ha_url}/api/states",
                          headers: {
                            'Authorization' => "Bearer #{ha_token}",
                            'Content-Type' => 'application/json'
                          },
                          timeout: 10)

  puts "Status: #{response.code}"

  if response.code == 200
    states = JSON.parse(response.body)
    puts "✅ Found #{states.length} entities!"

    # Show first few entities
    puts "\nFirst 5 entities:"
    states.first(5).each do |entity|
      puts "  - #{entity['entity_id']}: #{entity['state']}"
    end
  else
    puts "❌ States request failed: #{response.body}"
  end
rescue StandardError => e
  puts "❌ States error: #{e.message}"
end

# Test config endpoint
puts "\n3. Testing config endpoint..."
begin
  response = HTTParty.get("http://#{ha_url}/api/config",
                          headers: {
                            'Authorization' => "Bearer #{ha_token}",
                            'Content-Type' => 'application/json'
                          },
                          timeout: 10)

  puts "Status: #{response.code}"

  if response.code == 200
    config = JSON.parse(response.body)
    puts '✅ Config retrieved!'
    puts "  - Version: #{config['version']}"
    puts "  - Location: #{config['location_name']}"
    puts "  - Time Zone: #{config['time_zone']}"
  else
    puts "❌ Config request failed: #{response.body}"
  end
rescue StandardError => e
  puts "❌ Config error: #{e.message}"
end

puts "\n#{'=' * 40}"
puts 'Test complete! 🎲'
