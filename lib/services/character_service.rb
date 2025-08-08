# frozen_string_literal: true

require_relative '../home_assistant_client'

module Services
  class CharacterService
    # TTS provider types
    TTS_PROVIDERS = {
      cloud: :cloud, # Default Azure Cognitive Services via Home Assistant
      elevenlabs: :elevenlabs # ElevenLabs via Home Assistant
    }.freeze

    # Character definitions with voice configurations
    CHARACTERS = {
      default: {
        name: 'Glitch Cube',
        description: 'Sentient interactive art installation with curiosity',
        tts_provider: :cloud,
        voice: 'JennyNeural',
        language: 'en-US',
        speed: 100,
        volume: 0.7,
        personality_traits: {
          energy: :balanced,
          formality: :casual,
          humor: :playful
        },
        tools: %w[test_tool lighting_control camera_control display_control home_assistant speech_synthesis conversation_feedback]
      },

      buddy: {
        name: 'BUDDY',
        description: 'The Helper Cube - Naive assistant with broken profanity filter',
        tts_provider: :cloud,
        voice: 'DavisNeural', # Upbeat male voice
        language: 'en-US',
        speed: 110, # Speaks fast with enthusiasm
        volume: 0.8,
        personality_traits: {
          energy: :high,
          formality: :corporate_casual, # Mix of formal and profanity
          humor: :unintentional
        },
        # voice_style: 'excited', # Disabled for now - using plain voice
        chime: 'notification', # Helper notification sounds
        tools: %w[error_handling test_tool lighting_control music_control home_assistant display_control speech_synthesis conversation_feedback]
      },

      jax: {
        name: 'Jax the Juke',
        description: 'Surly bartender persona from asteroid belt dive bar',
        tts_provider: :cloud,
        voice: 'GuyNeural', # Gruff male voice
        language: 'en-US',
        speed: 95, # Slower, deliberate speech
        volume: 0.6, # Quieter, bar atmosphere
        personality_traits: {
          energy: :low,
          formality: :street,
          humor: :sarcastic
        },
        # voice_style: nil, # No style modifier for now
        alternate_provider: :piper, # For that analog warmth
        alternate_voice: 'en_US-lessac-medium', # Deeper Piper voice
        tools: %w[error_handling music_control lighting_control home_assistant test_tool speech_synthesis conversation_feedback]
      },

      lomi: {
        name: 'LOMI (The Glitch Bitch)',
        description: 'Glitchy cosmic drag queen diva trapped in cube',
        tts_provider: :cloud,
        voice: 'AriaNeural', # Dramatic female voice
        language: 'en-US',
        speed: 105,
        volume: 0.9, # LOUD and proud
        personality_traits: {
          energy: :extreme,
          formality: :theatrical,
          humor: :shade
        },
        # voice_style: 'excited', # Disabled for now - using plain voice
        glitch_effects: true, # Special processing for glitches
        chime: 'runway', # Ballroom/runway sounds
        tools: %w[error_handling lighting_control display_control camera_control music_control home_assistant speech_synthesis conversation_feedback]
      },

      zorp: {
        name: 'ZORP',
        description: 'The Slacker God - Divine party bro',
        tts_provider: :elevenlabs, # Use ElevenLabs as primary
        voice: 'Josh', # ElevenLabs voice name (mapped to ID in HomeAssistantClient)
        language: 'en-US', # Not used by ElevenLabs but kept for consistency
        speed: 90, # Slow, drawn-out delivery
        volume: 0.7,
        personality_traits: {
          energy: :chill,
          formality: :bro,
          humor: :cosmic
        },
        reverb: true, # Divine echo effects
        alternate_provider: :cloud,       # Fallback to cloud
        alternate_voice: 'DavisNeural',   # Azure fallback
        alternate_style: 'friendly', # Azure style for fallback
        tools: %w[error_handling test_tool lighting_control music_control home_assistant display_control speech_synthesis conversation_feedback]
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

    # Mood to voice style mapping (migrated from TTSService)
    MOOD_TO_VOICE_SUFFIX = {
      # Emotional states
      friendly: 'friendly',
      angry: 'angry',
      sad: 'sad',
      excited: 'excited',
      cheerful: 'cheerful',
      terrified: 'terrified',
      hopeful: 'hopeful',

      # Speaking styles
      whisper: 'whispering',
      whispering: 'whispering',
      shouting: 'shouting',
      unfriendly: 'unfriendly',

      # Professional styles
      assistant: 'assistant',
      chat: 'chat',
      customerservice: 'customerservice',
      newscast: 'newscast',

      # Aria-specific
      empathetic: 'empathetic',
      narration: 'narration-professional',
      newscast_casual: 'newscast-casual',
      newscast_formal: 'newscast-formal',

      # No variant
      neutral: nil,
      normal: nil,
      default: nil
    }.freeze

    # Voices that support emotional variants (migrated from TTSService)
    VOICES_WITH_VARIANTS = {
      # US English voices with variants
      'JennyNeural' => %w[assistant chat customerservice newscast angry cheerful sad excited friendly terrified shouting unfriendly whispering hopeful],
      'AriaNeural' => %w[chat customerservice narration-professional newscast-casual newscast-formal cheerful empathetic angry sad excited friendly terrified shouting unfriendly whispering hopeful],
      'DavisNeural' => %w[chat angry cheerful excited friendly hopeful sad shouting terrified unfriendly whispering],
      'GuyNeural' => %w[newscast angry cheerful sad excited friendly terrified shouting unfriendly whispering hopeful],

      # British English voices with variants
      'RyanNeural' => %w[cheerful chat whispering sad],
      'SoniaNeural' => %w[cheerful sad],

      # Indian English voice with variants
      'NeerjaNeural' => %w[newscast cheerful empathetic]
    }.freeze

    attr_reader :character, :home_assistant

    def initialize(character: :default, home_assistant: nil)
      @character = character.to_sym
      @character_config = CHARACTERS[@character] || CHARACTERS[:default]
      @home_assistant = home_assistant || HomeAssistantClient.new
    end

    # Speak as the character with optional context
    def speak(message, context: nil, **options)
      # Apply character-specific text processing
      message = process_message_for_character(message)

      # Apply glitch effects for LOMI
      message = apply_glitch_effects(message) if @character == :lomi && @character_config[:glitch_effects]

      # Get entity from options or use default
      entity_id = options[:entity_id] || 'media_player.square_voice'

      # Determine contextual mood (existing logic)
      options[:mood] || determine_mood(context)

      # Determine TTS provider and voice
      provider = options[:tts_provider] || @character_config[:tts_provider] || :cloud

      # Build simple provider specification for HomeAssistantClient
      voice_options = if provider == :elevenlabs
                        {
                          tts: :elevenlabs,
                          voice: @character_config[:voice], # ElevenLabs voice name
                          language: @character_config[:language] || 'en-US'
                        }
                      else
                        # Cloud provider (Azure Cognitive Services)
                        # For now, just use plain voice without mood styling
                        {
                          tts: :cloud,
                          voice: @character_config[:voice], # Plain voice without style
                          language: @character_config[:language] || 'en-US'
                        }
                      end

      # Use Home Assistant client - it will handle provider-specific implementation
      @home_assistant.speak(message, entity_id: entity_id, voice_options: voice_options)
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
        voice: @character_config[:voice],
        language: @character_config[:language] || 'en-US',
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

    # Get tools for a specific character, including base tools
    def self.get_character_tools(character_name)
      character = CHARACTERS[character_name.to_sym] || CHARACTERS[:default]
      character_tools = character[:tools] || []

      # Always include error_handling as a base tool if not already present
      base_tools = %w[error_handling]
      (base_tools + character_tools).uniq
    end

    # Check if a voice supports a specific variant (migrated from TTSService)
    def voice_supports_variant?(voice_name, variant)
      return false unless VOICES_WITH_VARIANTS.key?(voice_name)

      VOICES_WITH_VARIANTS[voice_name].include?(variant.to_s)
    end

    # Get best voice for mood with intelligent fallback logic (migrated from TTSService)
    def best_voice_for_mood(mood, preferred_voice_id)
      return preferred_voice_id unless mood

      suffix = MOOD_TO_VOICE_SUFFIX[mood.to_sym]
      return preferred_voice_id unless suffix

      # Try preferred voice first
      return "#{preferred_voice_id}||#{suffix}" if voice_supports_variant?(preferred_voice_id, suffix)

      # Fallback to JennyNeural (has most variants)
      return "JennyNeural||#{suffix}" if voice_supports_variant?('JennyNeural', suffix)

      # Fallback to AriaNeural
      return "AriaNeural||#{suffix}" if voice_supports_variant?('AriaNeural', suffix)

      # No voice supports this variant, use base voice
      preferred_voice_id
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
        message += ' *grumbles*' if rand > 0.8
      when :zorp
        # Add "like" randomly
        if rand > 0.7
          words = message.split
          insert_index = rand(1...[words.length, 1].max)
          words.insert(insert_index, 'like,')
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
