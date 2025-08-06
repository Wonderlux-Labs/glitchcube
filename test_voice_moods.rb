#!/usr/bin/env ruby
# frozen_string_literal: true

# Test the comprehensive voice mood mapping

require 'bundler/setup'
require 'dotenv'
Dotenv.load

require_relative 'app'

tts = Services::TTSService.new

puts '=' * 50
puts 'Voice Mood Mapping Test'
puts '=' * 50

# Test different moods with appropriate messages
test_cases = [
  { mood: :friendly, message: 'Hey there! So nice to meet you!' },
  { mood: :excited, message: 'Oh wow, this is absolutely amazing!' },
  { mood: :sad, message: "I'm feeling a bit down today." },
  { mood: :cheerful, message: 'What a beautiful day it is!' },
  { mood: :whisper, message: 'Can you keep a secret?' },
  { mood: :angry, message: 'This is really frustrating!' },
  { mood: :hopeful, message: 'I believe things will get better.' },
  { mood: :empathetic, message: 'I understand how you feel.', voice: :aria },
  { mood: :newscast, message: 'Breaking news just in.', voice: :guy },
  { mood: :terrified, message: 'Did you hear that noise?', voice: :davis }
]

puts "\n🎭 Testing mood-based voice selection:\n\n"

test_cases.each_with_index do |test, idx|
  mood = test[:mood]
  message = test[:message]
  voice = test[:voice] || :jenny

  puts "Test #{idx + 1}: #{mood.to_s.capitalize} mood"
  puts "  Voice: #{voice}"
  puts "  Message: \"#{message}\""

  begin
    # Use the TTS service with mood
    result = if test[:voice]
               tts.speak(message, mood: mood, voice: voice)
             else
               tts.speak(message, mood: mood)
             end

    if result
      puts '  ✅ Success!'
    else
      puts '  ❌ Failed'
    end
  rescue StandardError => e
    puts "  💥 Error: #{e.message}"
  end

  # Wait between tests
  sleep(3) if idx < test_cases.length - 1
  puts ''
end

# Show available variants for key voices
puts '=' * 50
puts 'Available Voice Variants'
puts '=' * 50

%w[JennyNeural AriaNeural DavisNeural GuyNeural].each do |voice|
  variants = tts.available_variants_for(voice)
  puts "\n#{voice}:"
  if variants.any?
    puts "  Variants: #{variants.join(', ')}"
  else
    puts '  No variants available'
  end
end

puts "\n✨ Test complete!"
puts "\n💡 Listen for the emotional differences in each voice!"
