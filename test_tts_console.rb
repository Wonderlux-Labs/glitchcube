# frozen_string_literal: true

# Test TTS Service in console
require_relative 'lib/services/tts_service'

puts '🎤 Testing TTS Service'
puts '=' * 50

tts = Services::TTSService.new

# Test 1: Basic TTS
puts "\n1️⃣ Testing basic TTS..."
result = tts.speak('Hello from the Glitch Cube! Testing the Home Assistant script.')
puts result ? '✅ Basic TTS succeeded' : '❌ Basic TTS failed'

# Test 2: Voice with variant
puts "\n2️⃣ Testing voice variant (JennyNeural||cheerful)..."
result = tts.speak("I'm feeling so happy and cheerful today!", voice: 'JennyNeural||cheerful')
puts result ? '✅ Voice variant succeeded' : '❌ Voice variant failed'

# Test 3: Mood-based voice
puts "\n3️⃣ Testing mood (should auto-select variant)..."
result = tts.speak('This is an excited message!', mood: :excited)
puts result ? '✅ Excited mood succeeded' : '❌ Excited mood failed'

puts "\n#{'=' * 50}"
puts '✅ TTS testing completed!'
