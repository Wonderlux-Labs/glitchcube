#!/usr/bin/env ruby

# Load the full application environment
require_relative 'config/environment'

puts "Testing TTS Service..."

# Test basic TTS
tts = Services::TTSService.new
success = tts.speak("Hello from the new TTS service! Can you hear me?")
puts "Basic TTS: #{success ? 'Success' : 'Failed'}"

sleep 2

# Test with mood
success = tts.speak("This is an excited message!", mood: :excited)
puts "Excited mood: #{success ? 'Success' : 'Failed'}"

sleep 2

# Test character service
character = Services::CharacterService.new
character.speak_as(:buddy, "Hey there! BUDDY here, testing the f***ing character voices!")
puts "BUDDY character: Done"

sleep 2

character.speak_as(:jax, "Yeah, whatever. Jax here. You want a drink or what?")
puts "Jax character: Done"

puts "Test complete!"