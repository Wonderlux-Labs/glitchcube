#!/usr/bin/env ruby
# frozen_string_literal: true

# Load the full app environment
require './app'

puts '🎤 Testing TTS Service with Home Assistant Script'
puts '=' * 50

# Initialize TTS service
tts = Services::TTSService.new

# Test 1: Basic TTS
puts "\n1️⃣ Testing basic TTS..."
success = tts.speak('Hello from the Glitch Cube! Testing the new Home Assistant script integration.')
puts success ? '✅ Basic TTS succeeded' : '❌ Basic TTS failed'
sleep 3

# Test 2: Voice with variant (|| separator)
puts "\n2️⃣ Testing voice variant (JennyNeural||cheerful)..."
success = tts.speak(
  "I'm feeling so happy and cheerful today!",
  voice: 'JennyNeural||cheerful'
)
puts success ? '✅ Voice variant succeeded' : '❌ Voice variant failed'
sleep 3

# Test 3: Mood-based voice selection
puts "\n3️⃣ Testing mood (should auto-select variant)..."
success = tts.speak('This is an excited message!', mood: :excited)
puts success ? '✅ Excited mood succeeded' : '❌ Excited mood failed'
sleep 3

# Test 4: Aria with customer service
puts "\n4️⃣ Testing AriaNeural||customerservice..."
success = tts.speak(
  'Hello, how may I assist you today?',
  voice: 'AriaNeural||customerservice'
)
puts success ? '✅ Aria customer service succeeded' : '❌ Aria customer service failed'
sleep 3

# Test 5: Whisper mode
puts "\n5️⃣ Testing whisper mode..."
success = tts.whisper('This is a secret whispered message.')
puts success ? '✅ Whisper succeeded' : '❌ Whisper failed'
sleep 3

# Test 6: Different voice (Guy)
puts "\n6️⃣ Testing GuyNeural voice..."
success = tts.speak('This is Guy speaking with a male voice.', voice: :guy)
puts success ? '✅ Guy voice succeeded' : '❌ Guy voice failed'
sleep 3

# Test 7: Character service test (disabled for now - hanging issue)
# if defined?(Services::CharacterService)
#   puts "\n7️⃣ Testing character voices..."
#
#   # Create BUDDY character and speak
#   buddy = Services::CharacterService.new(:buddy)
#   buddy.speak("Hey there! BUDDY here, testing the character system!")
#   puts "✅ BUDDY character done"
#   sleep 3
#
#   # Create Jax character and speak
#   jax = Services::CharacterService.new(:jax)
#   jax.speak("Yeah, whatever. Jax here. This better work.")
#   puts "✅ Jax character done"
# end

puts "\n#{'=' * 50}"
puts '✅ TTS testing completed!'
puts "\n📝 Check Home Assistant for any errors and verify audio output."
