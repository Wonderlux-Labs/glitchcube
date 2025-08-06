# frozen_string_literal: true

# Example usage of TTSService in GlitchCube conversations

require_relative 'tts_service'

# Initialize the service (typically done once in app initialization)
tts = Services::TTSService.new(
  default_provider: :cloud,
  default_voice: :jenny,
  default_entity: 'media_player.square_voice'
)

# Basic usage - simple speech
tts.speak("Hello, I'm GlitchCube!")

# With mood - affects voice style and speed
tts.speak("I'm so happy to meet you!", mood: :excited)
tts.speak("I'm feeling a bit lonely...", mood: :sad)
tts.speak("This is a secret", mood: :whisper)

# With specific voice
tts.speak("Let me try a different voice", voice: :aria)
tts.speak("Or perhaps this one", voice: :davis)

# With custom Azure neural voice (2025 expanded catalog)
tts.speak("Using a specific Azure voice", voice: "GuyNeural")

# With volume control
tts.speak("This is louder", volume: 0.9)
tts.speak("And this is quieter", volume: 0.3)

# With language selection
tts.speak("Bonjour!", language: "fr-FR", voice: "DeniseNeural")

# Using chime_tts for zero-lag announcements
tts.speak(
  "Someone is at the door",
  chime: "doorbell",
  announce: true,
  provider: :chime
)

# With custom speed
tts.speak("Speaking very quickly now", speed: 120)
tts.speak("And now... much... slower", speed: 80)

# Convenience methods
tts.speak_friendly("How are you doing today?")
tts.speak_excited("That's amazing!")
tts.whisper("Don't tell anyone...")
tts.announce("Attention everyone!")

# Broadcasting to multiple rooms
tts.broadcast(
  "Dinner is ready!",
  entities: ['media_player.kitchen', 'media_player.living_room', 'media_player.bedroom']
)

# Context-aware conversation example
class ConversationHandler
  attr_reader :tts
  
  def initialize
    @tts = Services::TTSService.new
  end
  
  def respond_to_user(message, context = {})
    mood = determine_mood(context)
    voice = context[:preferred_voice] || :jenny
    
    # Speak with appropriate mood and voice
    @tts.speak(
      message,
      mood: mood,
      voice: voice,
      volume: context[:volume] || 0.7
    )
  end
  
  def greet_user(time_of_day)
    case time_of_day
    when :morning
      @tts.speak_friendly("Good morning! Ready for a great day?")
    when :evening
      @tts.speak("Good evening", mood: :friendly, speed: 95)
    when :night
      @tts.whisper("Good night, sleep well")
    end
  end
  
  def alert_user(severity, message)
    case severity
    when :critical
      @tts.speak(message, mood: :angry, volume: 0.9, chime: "alert")
    when :warning
      @tts.speak(message, mood: :neutral, chime: "warning")
    when :info
      @tts.speak(message, mood: :friendly)
    end
  end
  
  private
  
  def determine_mood(context)
    return context[:mood] if context[:mood]
    
    case context[:emotion]
    when :happy then :excited
    when :sad then :sad
    when :angry then :angry
    when :calm then :neutral
    else :friendly
    end
  end
end

# Integration with GlitchCube personality
module GlitchCubeTTS
  class PersonalityVoice
    PERSONALITY_VOICES = {
      playful: { voice: :jenny, mood: :excited, speed: 105 },
      philosophical: { voice: :davis, mood: :neutral, speed: 95 },
      mysterious: { voice: :aria, mood: :whisper, speed: 90 },
      energetic: { voice: :guy, mood: :excited, speed: 110 }
    }.freeze
    
    def initialize(tts_service = nil)
      @tts = tts_service || Services::TTSService.new
    end
    
    def speak_as_personality(message, personality = :playful)
      config = PERSONALITY_VOICES[personality] || PERSONALITY_VOICES[:playful]
      
      @tts.speak(
        message,
        **config
      )
    end
    
    # Adaptive speaking based on battery level
    def speak_with_energy_awareness(message, battery_level)
      if battery_level < 20
        # Low energy, speak slowly and sadly
        @tts.speak(message, mood: :sad, speed: 85, volume: 0.5)
      elsif battery_level < 50
        # Medium energy, normal speech
        @tts.speak(message, mood: :neutral)
      else
        # High energy, excited speech
        @tts.speak(message, mood: :excited, speed: 105)
      end
    end
    
    # Time-aware speaking
    def speak_time_aware(message)
      hour = Time.now.hour
      
      if hour >= 22 || hour < 7
        # Night time - whisper
        @tts.whisper(message)
      elsif hour >= 7 && hour < 12
        # Morning - friendly and energetic
        @tts.speak(message, mood: :excited, speed: 105)
      elsif hour >= 12 && hour < 17
        # Afternoon - normal
        @tts.speak(message, mood: :friendly)
      else
        # Evening - calm
        @tts.speak(message, mood: :neutral, speed: 95)
      end
    end
  end
end