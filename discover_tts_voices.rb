#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to discover available TTS voices in Home Assistant

require 'bundler/setup'
require 'dotenv'
require 'net/http'
require 'json'

Dotenv.load

# Load the app and dependencies
require_relative 'app'

puts "=" * 50
puts "TTS Voice Discovery"
puts "=" * 50

# Test various voice names to see what works
test_voices = [
  # Base voices
  "JennyNeural",
  "AriaNeural",
  "GuyNeural",
  "DavisNeural",
  
  # Try different naming patterns for emotional variants
  "JennyNeural-Friendly",
  "JennyNeural-friendly",
  "en-US-JennyNeural-Friendly",
  "en-US-Jenny-Friendly",
  "Jenny-Friendly",
  "JennyFriendly",
  "JennyNeuralFriendly",
  
  # Try the angry variant
  "JennyNeural-Angry",
  "JennyNeural-angry",
  "en-US-JennyNeural-Angry",
  
  # Try sad
  "JennyNeural-Sad",
  "JennyNeural-sad",
  
  # Try whisper
  "JennyNeural-Whispering",
  "JennyNeural-Whisper",
  "JennyNeural-whisper",
  
  # Try some Azure-style names
  "en-US-JennyNeural",
  "en-US-AriaNeural",
  
  # Try with style suffix that Azure uses
  "Jenny:Friendly",
  "JennyNeural:Friendly",
  "JennyNeural:style=friendly"
]

tts = Services::TTSService.new
client = HomeAssistantClient.new

puts "\n🔍 Testing voice variants..."
puts "Will test with message: 'Testing voice'\n\n"

successful_voices = []
failed_voices = []

test_voices.each do |voice_name|
  print "Testing '#{voice_name}'... "
  
  begin
    # Try calling TTS with this voice
    service_data = {
      entity_id: "tts.home_assistant_cloud",
      media_player_entity_id: "media_player.square_voice",
      message: "Testing voice",
      language: "en-US",
      cache: false,
      options: { voice: voice_name }
    }
    
    result = client.call_service('tts', 'speak', service_data)
    
    if result
      puts "✅ SUCCESS"
      successful_voices << voice_name
    else
      puts "❌ FAILED (returned false/nil)"
      failed_voices << { voice: voice_name, error: "No response" }
    end
    
  rescue => e
    error_msg = e.message
    # Extract just the relevant error part
    if error_msg.include?("Bad Request")
      error_msg = "Bad Request - voice not recognized"
    elsif error_msg.include?("500")
      error_msg = "Server error - invalid voice format"
    end
    
    puts "❌ ERROR: #{error_msg}"
    failed_voices << { voice: voice_name, error: error_msg }
  end
  
  # Small delay to not spam the API
  sleep(0.5)
end

puts "\n" + "=" * 50
puts "Results Summary"
puts "=" * 50

puts "\n✅ Working voices (#{successful_voices.length}):"
successful_voices.each do |voice|
  puts "   - #{voice}"
end

puts "\n❌ Failed voices (#{failed_voices.length}):"
failed_voices.each do |item|
  puts "   - #{item[:voice]}: #{item[:error]}"
end

# Try to get TTS provider info if available
puts "\n" + "=" * 50
puts "Checking TTS Provider Info"
puts "=" * 50

begin
  # Try to get the list of TTS engines
  states = client.states
  tts_entities = states.select { |s| s['entity_id'].start_with?('tts.') }
  
  puts "\nAvailable TTS entities:"
  tts_entities.each do |entity|
    puts "  - #{entity['entity_id']}"
    if entity['attributes']
      puts "    Attributes: #{entity['attributes'].keys.join(', ')}"
    end
  end
rescue => e
  puts "Could not fetch TTS entity info: #{e.message}"
end

puts "\n✨ Discovery complete!"