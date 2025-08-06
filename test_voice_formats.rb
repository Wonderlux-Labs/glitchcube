#!/usr/bin/env ruby
# frozen_string_literal: true

# Test different voice format patterns to see which produces different sounds

require 'bundler/setup'
require 'dotenv'
Dotenv.load

require_relative 'app'

client = HomeAssistantClient.new

formats_to_test = [
  # Base voice
  { name: "Base JennyNeural", voice: "JennyNeural" },
  
  # Double pipe separator (from code)
  { name: "Double pipe lowercase", voice: "JennyNeural||friendly" },
  { name: "Double pipe capitalized", voice: "JennyNeural||Friendly" },
  
  # Single hyphen (common pattern)
  { name: "Hyphen capitalized", voice: "JennyNeural-Friendly" },
  { name: "Hyphen lowercase", voice: "JennyNeural-friendly" },
  
  # With language prefix
  { name: "Language prefix double pipe", voice: "en-US-JennyNeural||friendly" },
  { name: "Language prefix hyphen", voice: "en-US-JennyNeural-Friendly" },
  
  # Parentheses (as shown in UI?)
  { name: "Parentheses", voice: "JennyNeural (friendly)" },
  
  # Space separated
  { name: "Space separated", voice: "JennyNeural Friendly" },
]

puts "=" * 50
puts "Testing Voice Format Patterns"
puts "=" * 50
puts "\nTesting with message: 'Hello, testing voice format'\n\n"

formats_to_test.each do |format|
  puts "📢 Testing: #{format[:name]}"
  puts "   Voice string: '#{format[:voice]}'"
  
  begin
    service_data = {
      entity_id: "tts.home_assistant_cloud",
      media_player_entity_id: "media_player.square_voice",
      message: "Hello, testing voice format",
      language: "en-US",
      cache: false,
      options: { voice: format[:voice] }
    }
    
    result = client.call_service('tts', 'speak', service_data)
    
    if result
      puts "   ✅ Worked!"
    else
      puts "   ⚠️  Returned false/nil"
    end
    
  rescue => e
    error_msg = e.message.include?("Bad Request") ? "Bad Request" : e.message[0..50]
    puts "   ❌ Error: #{error_msg}"
  end
  
  # Pause between tests
  sleep(2)
  puts ""
end

puts "💡 Listen for which ones sound different!"
puts "   The ones that work AND sound different are using the correct format."
puts "\n✨ Done!"