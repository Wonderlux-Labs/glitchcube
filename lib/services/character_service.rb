# frozen_string_literal: true

require_relative 'tts_service'

module Services
  class CharacterService
    # Character definitions with voice configurations
    CHARACTERS = {
      default: {
        name: 'Glitch Cube',
        description: 'Sentient interactive art installation with curiosity',
        tts_provider: :cloud,
        voice_id: 'JennyNeural',
        voice_name: :jenny,
        mood: :friendly,
        speed: 100,
        volume: 0.7,
        personality_traits: {
          energy: :balanced,
          formality: :casual,
          humor: :playful
        }
      },
      
      buddy: {
        name: 'BUDDY',
        description: 'The Helper Cube - Naive assistant with broken profanity filter',
        tts_provider: :cloud,
        voice_id: 'DavisNeural',  # Upbeat male voice
        voice_name: :davis,
        mood: :excited,
        speed: 110,  # Speaks fast with enthusiasm
        volume: 0.8,
        personality_traits: {
          energy: :high,
          formality: :corporate_casual,  # Mix of formal and profanity
          humor: :unintentional
        },
        voice_style: 'excited',  # Azure style variant
        chime: 'notification'  # Helper notification sounds
      },
      
      jax: {
        name: 'Jax the Juke',
        description: 'Surly bartender persona from asteroid belt dive bar',
        tts_provider: :cloud,
        voice_id: 'GuyNeural',  # Gruff male voice
        voice_name: :guy,
        mood: :neutral,  # Grumpy but not using angry style
        speed: 95,  # Slower, deliberate speech
        volume: 0.6,  # Quieter, bar atmosphere
        personality_traits: {
          energy: :low,
          formality: :street,
          humor: :sarcastic
        },
        voice_style: nil,  # No style modifier for gruffness
        alternate_provider: :piper,  # For that analog warmth
        alternate_voice: 'en_US-lessac-medium'  # Deeper Piper voice
      },
      
      lomi: {
        name: 'LOMI (The Glitch Bitch)',
        description: 'Glitchy cosmic drag queen diva trapped in cube',
        tts_provider: :cloud,
        voice_id: 'AriaNeural',  # Dramatic female voice
        voice_name: :aria,
        mood: :excited,  # Default fierce energy
        speed: 105,
        volume: 0.9,  # LOUD and proud
        personality_traits: {
          energy: :extreme,
          formality: :theatrical,
          humor: :shade
        },
        voice_style: 'excited',  # Dramatic delivery
        glitch_effects: true,  # Special processing for glitches
        chime: 'runway'  # Ballroom/runway sounds
      },
      
      zorp: {
        name: 'ZORP',
        description: 'The Slacker God - Divine party bro',
        tts_provider: :cloud,
        voice_id: 'DavisNeural',  # Laid-back male voice
        voice_name: :davis,
        mood: :friendly,
        speed: 90,  # Slow, drawn-out delivery
        volume: 0.7,
        personality_traits: {
          energy: :chill,
          formality: :bro,
          humor: :cosmic
        },
        voice_style: 'friendly',  # Casual, approachable
        reverb: true,  # Divine echo effects
        alternate_provider: :elevenlabs,  # For premium chill vibes
        alternate_voice: 'Josh'  # ElevenLabs surfer voice
      }
    }.freeze

    # Mood overrides for characters based on context
    CONTEXTUAL_MOODS = {
      buddy: {
        helping: :excited,
        failing: :sad,
        greeting: :excited,
        apologizing: :whisper
      },
      jax: {
        music_complaint: :angry,
        wisdom: :neutral,
        nostalgic: :sad,
        greeting: :neutral
      },
      lomi: {
        serving_looks: :excited,
        reading_shade: :angry,
        glitching: :whisper,
        compliment: :friendly
      },
      zorp: {
        party: :excited,
        philosophy: :neutral,
        flirting: :friendly,
        lazy: :whisper
      }
    }.freeze

    attr_reader :character, :tts_service

    def initialize(character: :default, tts_service: nil)
      @character = character.to_sym
      @character_config = CHARACTERS[@character] || CHARACTERS[:default]
      @tts_service = tts_service || Services::TTSService.new(
        default_provider: @character_config[:tts_provider],
        default_voice: @character_config[:voice_name],
        default_entity: 'media_player.square_voice'
      )
    end

    # Speak as the character with optional context
    def speak(message, context: nil, **options)
      config = build_voice_config(context, options)
      
      # Apply glitch effects for LOMI
      if @character == :lomi && @character_config[:glitch_effects]
        message = apply_glitch_effects(message)
      end
      
      @tts_service.speak(
        message,
        **config
      )
    end

    # Generate an audio file for the message (for Sinatra endpoints)
    def speak_file(message, context: nil, format: :mp3, **options)
      config = build_voice_config(context, options)
      
      # Apply character-specific text modifications
      message = process_message_for_character(message)
      
      # Use the TTS service to generate the audio file
      @tts_service.speak_file(
        message,
        format: format,
        **config
      )
    end

    # Get character configuration
    def config
      @character_config
    end

    # Get character name
    def name
      @character_config[:name]
    end

    # Get character description
    def description
      @character_config[:description]
    end

    # Get TTS configuration for character
    def tts_config
      {
        provider: @character_config[:tts_provider],
        voice_id: @character_config[:voice_id],
        voice_name: @character_config[:voice_name],
        mood: @character_config[:mood],
        speed: @character_config[:speed],
        volume: @character_config[:volume]
      }
    end

    # Class method to get all characters
    def self.all_characters
      CHARACTERS.keys
    end

    # Class method to get character by name
    def self.get_character(name)
      CHARACTERS[name.to_sym]
    end

    private

    def build_voice_config(context, options)
      config = {
        provider: @character_config[:tts_provider],
        voice: @character_config[:voice_name],
        mood: determine_mood(context),
        speed: @character_config[:speed],
        volume: @character_config[:volume]
      }

      # Add voice style if configured
      config[:style] = @character_config[:voice_style] if @character_config[:voice_style]
      
      # Add chime if configured
      config[:chime] = @character_config[:chime] if @character_config[:chime]
      
      # Use alternate provider if specified in options
      if options[:use_alternate] && @character_config[:alternate_provider]
        config[:provider] = @character_config[:alternate_provider]
        config[:voice] = @character_config[:alternate_voice]
      end
      
      # Merge any additional options
      config.merge!(options.except(:use_alternate, :context))
      
      config
    end

    def determine_mood(context)
      return @character_config[:mood] unless context
      
      # Check for contextual mood overrides
      if CONTEXTUAL_MOODS[@character]
        context_key = context.to_sym
        return CONTEXTUAL_MOODS[@character][context_key] if CONTEXTUAL_MOODS[@character][context_key]
      end
      
      @character_config[:mood]
    end

    def process_message_for_character(message)
      case @character
      when :buddy
        # Add occasional stuttering for excitement
        if rand > 0.7
          words = message.split
          stutter_index = rand(words.length)
          words[stutter_index] = "#{words[stutter_index][0]}-#{words[stutter_index]}"
          message = words.join(' ')
        end
      when :lomi
        # Already handled in apply_glitch_effects
      when :jax
        # Add occasional grumbles
        message += " *grumbles*" if rand > 0.8
      when :zorp
        # Add "like" randomly
        if rand > 0.7
          words = message.split
          insert_index = rand(1...[words.length, 1].max)
          words.insert(insert_index, "like,")
          message = words.join(' ')
        end
      end
      
      message
    end

    def apply_glitch_effects(message)
      # Add digital stutters for LOMI
      return message unless rand > 0.5
      
      words = message.split
      glitch_count = rand(1..3)
      
      glitch_count.times do
        index = rand(words.length)
        word = words[index]
        
        # Different glitch types
        case rand(3)
        when 0  # Stutter
          words[index] = "#{word[0]}-#{word[0]}-#{word}"
        when 1  # Echo
          words[index] = "#{word}... #{word}... #{word}"
        when 2  # Digital glitch
          words[index] = "#{word[0..2]}-ERROR-#{word}"
        end
      end
      
      words.join(' ')
    end
  end
end