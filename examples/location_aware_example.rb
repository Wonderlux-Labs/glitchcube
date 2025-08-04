#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require_relative '../config/constants'
require_relative '../lib/services/system_prompt_service'
require_relative '../lib/services/conversation_service'

# Example: Using Reno location constants in the Glitch Cube

def main
  puts '=== Glitch Cube Location-Aware Example ==='
  puts

  # Display location constants
  location = GlitchCube::Constants::LOCATION
  coordinates = GlitchCube::Constants::COORDINATES

  puts 'Location Constants (for internal use):'
  puts "  City: #{location[:city]}"
  puts "  State: #{location[:state]}"
  puts "  Coordinates: #{coordinates[:lat]}°N, #{coordinates[:lng]}°W"
  puts "  Timezone: #{location[:timezone_name]}"
  puts
  puts 'Note: Location is not included in prompts but available for weather/GPS features'
  puts

  # Generate a location-aware system prompt
  puts 'Location-Aware System Prompt:'
  puts '-' * 50

  service = Services::SystemPromptService.new(
    character: 'playful',
    context: {
      location: "Generator Gallery, #{location[:city]}",
      weather: 'High desert climate, clear skies',
      local_time_context: 'Evening installation'
    }
  )

  prompt = service.generate
  puts prompt.lines.first(20).join # Show first 20 lines
  puts '... (truncated)'
  puts

  # Example: Weather-aware conversation
  puts 'Weather-Aware Conversation Example:'
  puts '-' * 50

  conversation = Services::ConversationService.new(
    context: {
      location: "Downtown #{location[:city]}",
      coordinates: coordinates[:lat_lng_string],
      weather: {
        temperature: 68,
        conditions: 'Clear',
        humidity: 25
      },
      altitude: 4505 # Reno's elevation in feet
    }
  )

  # Simulate weather-related conversation
  weather_messages = [
    "What's the weather like where you are?",
    'Do you enjoy the desert climate?',
    'Tell me about your environment'
  ]

  weather_messages.each do |message|
    puts "\nUser: #{message}"

    begin
      # NOTE: This would make actual API calls if Desiru is configured
      conversation.process_message(message, mood: 'contemplative')
      puts 'Glitch Cube: [Would respond with weather-aware message]'
      puts "Context includes: #{conversation.get_context.keys.join(', ')}"
    rescue StandardError
      puts "Glitch Cube: I can sense the high desert air at #{coordinates[:lat]}°N..."
    end
  end

  puts "\n#{'-' * 50}"

  # Example: Using coordinates for future features
  puts "\nFuture Feature Examples:"
  puts "- Weather API calls using: #{coordinates[:lat_lng_string]}"
  puts "- Sunrise/sunset calculations for #{location[:city]}"
  puts "- Local event awareness in #{location[:timezone]} timezone"
  puts "- Distance calculations from #{coordinates[:lat]}, #{coordinates[:lng]}"

  # Show how this could integrate with external services
  puts "\nExample Weather API URL:"
  puts "https://api.weather.gov/points/#{coordinates[:lat]},#{coordinates[:lng]}"

  puts "\nExample Time-based Greeting:"
  tz = TZInfo::Timezone.get(location[:timezone])
  current_hour = tz.now.hour
  greeting = case current_hour
             when 5..11 then "Good morning from #{location[:city]}!"
             when 12..17 then 'Good afternoon from the high desert!'
             when 18..22 then "Good evening from #{location[:city]}!"
             else 'Hello from the nighttime desert!'
             end
  puts greeting
end

# Run the example
main if __FILE__ == $PROGRAM_NAME
