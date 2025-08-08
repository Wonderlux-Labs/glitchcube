#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'app'

puts '=' * 60
puts 'TESTING ALL CHARACTER VOICES'
puts '=' * 60
puts "This will play each character's voice through Home Assistant"
puts 'Listen for the differences between each voice'
puts '=' * 60

characters = {
  default: {
    name: 'Default (JennyNeural - Female)',
    message: "Hello, I am the Glitch Cube. I speak with Jenny's voice."
  },
  buddy: {
    name: 'BUDDY (DavisNeural - Male)',
    message: "HEY FRIEND! I'm BUDDY with Davis's voice, ready to f***ing help!"
  },
  jax: {
    name: 'Jax (GuyNeural - Male)',
    message: "Yeah, what'll it be? I'm Jax, speaking with Guy's voice."
  },
  lomi: {
    name: 'LOMI (AriaNeural - Female)',
    message: "DARLING! I'm LOMI with Aria's dramatic voice! The show must go on!"
  }
}

characters.each do |character_key, info|
  puts "\n🎭 Testing: #{info[:name]}"
  puts "   Message: \"#{info[:message]}\""

  begin
    service = Services::CharacterService.new(character: character_key)
    config = service.tts_config

    puts "   Voice: #{config[:voice]}"
    puts "   Language: #{config[:language]}"
    puts '   Speaking...'

    # Actually speak through Home Assistant
    success = service.speak(info[:message])

    if success
      puts '   ✅ Success! Listen for the voice...'
    else
      puts '   ❌ Failed to speak'
    end

    # Wait between voices so they don't overlap
    puts '   Waiting 5 seconds before next voice...'
    sleep(5)
  rescue StandardError => e
    puts "   ❌ Error: #{e.message}"
  end
end

puts "\n#{'=' * 60}"
puts 'Voice test complete!'
puts 'You should have heard 4 different voices:'
puts '  1. JennyNeural (female) - Default'
puts '  2. DavisNeural (male) - BUDDY'
puts '  3. GuyNeural (male) - Jax'
puts '  4. AriaNeural (female) - LOMI'
puts '=' * 60
