# frozen_string_literal: true

require 'securerandom'
require 'tmpdir'
require_relative '../home_assistant_client'
require_relative 'logger_service'
require_relative '../error_handler_integration'

module Services
  class TTSService
    include ErrorHandlerIntegration

    # Available TTS providers
    PROVIDERS = {
      cloud: 'tts.home_assistant_cloud',
      nabu_casa: 'tts.home_assistant_cloud', # alias
      google: 'tts.google_translate',
      piper: 'tts.piper',
      elevenlabs: 'tts.elevenlabs',
      chime: 'chime_tts'
    }.freeze

    # Available voices for Nabu Casa Cloud (2025 expanded catalog)
    # Organized by English variant
    CLOUD_VOICES = {
      # == US English (en-US) ==
      # Primary voices with extensive variant support
      jenny: 'JennyNeural',      # Female, default, most variants
      aria: 'AriaNeural',        # Female, empathetic option
      davis: 'DavisNeural',      # Male, warm
      guy: 'GuyNeural',          # Male, professional

      # Additional US voices
      amber: 'AmberNeural',      # Female
      ana: 'AnaNeural',          # Female child
      andrew: 'AndrewNeural',    # Male
      ashley: 'AshleyNeural',    # Female
      brandon: 'BrandonNeural',  # Male
      christopher: 'ChristopherNeural', # Male
      cora: 'CoraNeural', # Female
      elizabeth: 'ElizabethNeural', # Female
      emma: 'EmmaNeural',        # Female
      eric: 'EricNeural',        # Male
      jacob: 'JacobNeural',      # Male
      jane: 'JaneNeural',        # Female
      jason: 'JasonNeural',      # Male
      michelle: 'MichelleNeural', # Female
      monica: 'MonicaNeural',    # Female
      nancy: 'NancyNeural',      # Female
      roger: 'RogerNeural',      # Male
      sara: 'SaraNeural',        # Female
      steffan: 'SteffanNeural',  # Male
      tony: 'TonyNeural',        # Male

      # == British English (en-GB) ==
      abbi: 'AbbiNeural',        # Female
      alfie: 'AlfieNeural',      # Male
      bella: 'BellaNeural',      # Female
      elliot: 'ElliotNeural',    # Male
      ethan: 'EthanNeural',      # Male
      hollie: 'HollieNeural',    # Female
      libby: 'LibbyNeural',      # Female
      maisie: 'MaisieNeural',    # Female
      noah: 'NoahNeural',        # Male
      oliver: 'OliverNeural',    # Male
      olivia: 'OliviaNeural',    # Female
      ryan: 'RyanNeural',        # Male (has variants!)
      sonia: 'SoniaNeural',      # Female (has variants!)
      thomas: 'ThomasNeural',    # Male

      # == Australian English (en-AU) ==
      annette: 'AnnetteNeural',  # Female
      carly: 'CarlyNeural',      # Female
      darren: 'DarrenNeural',    # Male
      duncan: 'DuncanNeural',    # Male
      elsie: 'ElsieNeural',      # Female
      freya: 'FreyaNeural',      # Female
      joanne: 'JoanneNeural',    # Female
      ken: 'KenNeural',          # Male
      kim: 'KimNeural',          # Female
      natasha: 'NatashaNeural',  # Female
      neil: 'NeilNeural',        # Male
      tim: 'TimNeural',          # Male
      tina: 'TinaNeural',        # Female
      william: 'WilliamNeural',  # Male

      # == Indian English (en-IN) ==
      aarav: 'AaravNeural',      # Male
      aarti: 'AartiNeural',      # Female
      aashi: 'AashiNeural',      # Female
      ananya: 'AnanyaNeural',    # Female
      arjun: 'ArjunNeural',      # Male
      kavya: 'KavyaNeural',      # Female
      kunal: 'KunalNeural',      # Male
      neerja: 'NeerjaNeural',    # Female (has variants!)
      prabhat: 'PrabhatNeural',  # Male
      rehaan: 'RehaanNeural',    # Male

      # == Canadian English (en-CA) ==
      clara: 'ClaraNeural',      # Female
      liam: 'LiamNeural',        # Male

      # == Other English variants ==
      # Irish (en-IE)
      connor: 'ConnorNeural',    # Male
      emily_ie: 'EmilyNeural',   # Female

      # New Zealand (en-NZ)
      mitchell: 'MitchellNeural', # Male
      molly: 'MollyNeural', # Female

      # South African (en-ZA)
      leah: 'LeahNeural',        # Female
      luke: 'LukeNeural',        # Male

      # Multilingual voices (support variants)
      andrew_multi: 'AndrewMultilingualNeural',
      ava_multi: 'AvaMultilingualNeural',
      brian_multi: 'BrianMultilingualNeural',
      emma_multi: 'EmmaMultilingualNeural',

      # Default
      default: 'JennyNeural'
    }.freeze

    # Mood to voice variant mapping
    # These get appended to voice names with || separator
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

    # Voices that support emotional variants
    # Based on hass-nabucasa voice_data.py
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
      'NeerjaNeural' => %w[newscast cheerful empathetic],

      # Multilingual voices with variants
      'AndrewMultilingualNeural' => %w[angry cheerful excited friendly hopeful sad shouting terrified unfriendly whispering],
      'AvaMultilingualNeural' => %w[angry cheerful excited friendly hopeful sad shouting terrified unfriendly whispering],
      'BrianMultilingualNeural' => %w[angry cheerful excited friendly hopeful sad shouting terrified unfriendly whispering],
      'EmmaMultilingualNeural' => %w[angry cheerful excited friendly hopeful sad shouting terrified unfriendly whispering]
    }.freeze

    # Speech speed modifiers by mood
    MOOD_SPEEDS = {
      excited: 110,
      angry: 105,
      sad: 90,
      whisper: 85,
      neutral: 100
    }.freeze

    attr_reader :home_assistant, :default_provider, :default_voice, :default_entity

    def initialize(
      home_assistant: nil,
      default_provider: :cloud,
      default_voice: :jenny,
      default_entity: 'media_player.square_voice'
    )
      @home_assistant = home_assistant || HomeAssistantClient.new
      @default_provider = default_provider
      @default_voice = default_voice
      @default_entity = default_entity
    end

    # Main speak method with all options
    def speak(
      message,
      voice: nil,
      mood: nil,
      provider: nil,
      entity_id: nil,
      language: 'en-US',
      speed: nil,
      volume: nil,
      cache: true,
      announce: false,
      chime: nil,
      **options
    )
      return false if message.nil? || message.strip.empty?

      # Determine parameters
      provider ||= @default_provider
      voice ||= @default_voice
      entity_id ||= @default_entity

      # Apply mood-based voice selection
      # In HA Cloud, moods are implemented as separate voice variants using || separator
      if mood && MOOD_TO_VOICE_SUFFIX.key?(mood.to_sym) && %i[cloud nabu_casa].include?(provider.to_sym)
        suffix = MOOD_TO_VOICE_SUFFIX[mood.to_sym]
        if suffix
          # Get the base voice name
          base_voice_name = CLOUD_VOICES[voice.to_sym] || voice.to_s
          # Remove any existing style suffix if present
          base_voice_name = base_voice_name.split('||').first

          # Check if this voice supports the requested variant
          if voice_supports_variant?(base_voice_name, suffix)
            # Create mood-specific voice name with || separator
            mood_voice = "#{base_voice_name}||#{suffix}"
            # Use the mood-specific voice
            voice = mood_voice
            puts "🎭 Using mood-specific voice: #{mood_voice} for mood: #{mood}"
          else
            puts "⚠️  Voice #{base_voice_name} doesn't support #{suffix} variant, using base voice"
          end
        end
        speed ||= MOOD_SPEEDS[mood.to_sym]
      end

      speed ||= 100

      start_time = Time.now

      begin
        result = if chime || provider == :chime
                   speak_with_chime(
                     message: message,
                     voice: voice,
                     entity_id: entity_id,
                     language: language,
                     speed: speed,
                     volume: volume,
                     chime: chime,
                     announce: announce,
                     **options
                   )
                 else
                   speak_standard(
                     message: message,
                     provider: provider,
                     voice: voice,
                     entity_id: entity_id,
                     language: language,
                     speed: speed,
                     volume: volume,
                     cache: cache,
                     **options
                   )
                 end

        duration = ((Time.now - start_time) * 1000).round

        Services::LoggerService.log_tts(
          message: truncate_message(message),
          success: result,
          duration: duration,
          provider: provider.to_s,
          voice: voice.to_s,
          mood: mood&.to_s,
          entity_id: entity_id
        )

        result
      rescue StandardError => e
        duration = ((Time.now - start_time) * 1000).round

        Services::LoggerService.log_tts(
          message: truncate_message(message),
          success: false,
          duration: duration,
          error: e.message,
          provider: provider.to_s,
          voice: voice.to_s,
          mood: mood&.to_s,
          entity_id: entity_id
        )

        # Use self-healing error handler if enabled
        with_error_healing do
          handle_tts_error(e, message, entity_id)
        end
      end
    end

    # Convenience methods for specific moods
    def speak_friendly(message, **options)
      speak(message, mood: :friendly, **options)
    end

    def speak_excited(message, **options)
      speak(message, mood: :excited, **options)
    end

    def speak_sad(message, **options)
      speak(message, mood: :sad, **options)
    end

    def whisper(message, **options)
      speak(message, mood: :whisper, **options)
    end

    def announce(message, **options)
      speak(message, announce: true, **options)
    end

    # Multi-room announcement
    def broadcast(message, entities: nil, **options)
      entities ||= ['media_player.all_speakers']

      entities.map do |entity_id|
        speak(message, entity_id: entity_id, **options)
      end.all?
    end

    # Generate audio file for Sinatra endpoints
    def speak_file(
      message,
      voice: nil,
      mood: nil,
      provider: nil,
      language: 'en-US',
      speed: nil,
      format: :mp3,
      output_path: nil,
      **options
    )
      return nil if message.nil? || message.strip.empty?

      # Determine parameters
      provider ||= @default_provider
      voice ||= @default_voice

      # Apply mood-based modifications
      if mood && MOOD_STYLES.key?(mood.to_sym)
        options[:style] = MOOD_STYLES[mood.to_sym] if MOOD_STYLES[mood.to_sym]
        speed ||= MOOD_SPEEDS[mood.to_sym]
      end

      speed ||= 100

      # Generate output path if not provided
      output_path ||= generate_temp_audio_path(format)

      start_time = Time.now

      begin
        # Call Home Assistant TTS API to get audio file
        audio_url = generate_tts_audio_url(
          message: message,
          provider: provider,
          voice: voice,
          language: language,
          speed: speed,
          **options
        )

        # Download the audio file
        download_audio_file(audio_url, output_path)

        duration = ((Time.now - start_time) * 1000).round

        Services::LoggerService.log_tts(
          message: truncate_message(message),
          success: true,
          duration: duration,
          provider: provider.to_s,
          voice: voice.to_s,
          mood: mood&.to_s,
          output_file: output_path
        )

        output_path
      rescue StandardError => e
        duration = ((Time.now - start_time) * 1000).round

        Services::LoggerService.log_tts(
          message: truncate_message(message),
          success: false,
          duration: duration,
          error: e.message,
          provider: provider.to_s,
          voice: voice.to_s,
          mood: mood&.to_s
        )

        # Try fallback generation
        generate_fallback_audio(message, format)
      end
    end

    # Check if a voice supports a specific variant
    def voice_supports_variant?(voice_name, variant)
      return false unless VOICES_WITH_VARIANTS.key?(voice_name)

      VOICES_WITH_VARIANTS[voice_name].include?(variant.to_s)
    end

    # Get available variants for a voice
    def available_variants_for(voice_name)
      base_name = voice_name.to_s.split('||').first
      VOICES_WITH_VARIANTS[base_name] || []
    end

    # Get best voice for mood (with fallback logic)
    def best_voice_for_mood(mood, preferred_voice = :jenny)
      return CLOUD_VOICES[preferred_voice] unless mood

      suffix = MOOD_TO_VOICE_SUFFIX[mood.to_sym]
      return CLOUD_VOICES[preferred_voice] unless suffix

      # Try preferred voice first
      base_voice = CLOUD_VOICES[preferred_voice] || 'JennyNeural'
      return "#{base_voice}||#{suffix}" if voice_supports_variant?(base_voice, suffix)

      # Fallback to JennyNeural (has most variants)
      return "JennyNeural||#{suffix}" if voice_supports_variant?('JennyNeural', suffix)

      # Fallback to AriaNeural (has empathetic)
      return "AriaNeural||#{suffix}" if voice_supports_variant?('AriaNeural', suffix)

      # Final fallback to base voice
      base_voice
    end

    private

    def speak_standard(
      message:,
      provider:,
      voice:,
      entity_id:,
      language:,
      speed:,
      volume:,
      cache:,
      **options
    )
      provider_id = PROVIDERS[provider.to_sym] || provider.to_s

      # Build options hash based on provider
      tts_options = build_tts_options(
        provider: provider,
        voice: voice,
        speed: speed,
        **options
      )

      # Use Home Assistant script for cloud providers
      # This ensures we have the exact format Home Assistant expects
      if %i[cloud nabu_casa].include?(provider.to_sym)
        # Call our custom script that handles all the TTS complexity
        script_data = {
          message: message,
          media_player: entity_id,
          language: language,
          cache: cache
        }

        # Add voice if specified (supports variants like JennyNeural||cheerful)
        script_data[:voice] = tts_options[:voice] if !tts_options.empty? && tts_options[:voice]

        puts '📣 TTS Script Call:'
        puts "  Speaker: #{entity_id}"
        puts "  Message: #{truncate_message(message)}"
        puts "  Voice: #{tts_options[:voice]}" if tts_options[:voice]
        puts "  Script data: #{script_data.inspect}"

        # Call the Home Assistant script
        @home_assistant.call_service('script', 'glitchcube_tts', script_data)
      else
        # Legacy service call format for other providers
        service_data = {
          entity_id: entity_id,
          message: message,
          language: language,
          cache: cache
        }

        service_data[:options] = tts_options unless tts_options.empty?

        # Extract domain and service from provider_id
        domain, service = provider_id.split('.')
        service ||= 'say'

        @home_assistant.call_service(domain, service, service_data)
      end

      # Apply volume if specified
      if volume
        @home_assistant.call_service(
          'media_player',
          'volume_set',
          entity_id: entity_id,
          volume_level: volume
        )
      end

      true
    end

    def speak_with_chime(
      message:,
      voice:,
      entity_id:,
      language:,
      speed:,
      volume:,
      chime:,
      announce:,
      **options
    )
      chime_data = {
        entity_id: entity_id,
        message: message,
        tts_platform: options[:tts_platform] || 'tts.cloud',
        language: language,
        announce: announce
      }

      # Add chime path if specified
      chime_data[:chime_path] = chime if chime.is_a?(String)

      # Add voice options
      if voice
        voice_name = CLOUD_VOICES[voice.to_sym] || voice.to_s
        chime_data[:options] = "voice: #{voice_name}"
      end

      # Add speed adjustment
      chime_data[:tts_playbook_speed] = speed if speed && speed != 100

      # Add volume
      chime_data[:volume_level] = volume if volume

      # Add any additional options
      chime_data.merge!(options.except(:tts_platform))

      @home_assistant.call_service('chime_tts', 'say', chime_data)
      true
    end

    def build_tts_options(provider:, voice:, speed:, **_options)
      tts_options = {}

      # Add voice selection
      # Voice might already be a mood-specific variant like "JennyNeural||cheerful"
      if voice
        # Check if it's a symbol from our mapping or a direct string
        voice_name = if voice.is_a?(Symbol) && CLOUD_VOICES.key?(voice)
                       CLOUD_VOICES[voice]
                     else
                       voice.to_s
                     end
        tts_options[:voice] = voice_name
      end

      # NOTE: Home Assistant Cloud TTS doesn't support separate 'style' or 'speed' parameters
      # Emotional styles are handled via voice selection (e.g., JennyNeural||cheerful)
      # Speed adjustments would require SSML or different implementation

      tts_options
    end

    def handle_tts_error(error, message, entity_id)
      puts "⚠️  TTS failed for '#{truncate_message(message)}' on #{entity_id}: #{error.message}"

      # No Google TTS fallback - we don't have a key
      puts '❌ TTS completely failed - no fallback available'

      false
    end

    def truncate_message(message, max_length = 50)
      return message if message.length <= max_length

      "#{message[0...max_length]}..."
    end

    def generate_temp_audio_path(format)
      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      random_id = SecureRandom.hex(4)
      File.join(Dir.tmpdir, "tts_#{timestamp}_#{random_id}.#{format}")
    end

    def generate_tts_audio_url(message:, provider:, voice:, language:, speed:, **options)
      provider_id = PROVIDERS[provider.to_sym] || provider.to_s

      # Build request based on provider
      case provider.to_sym
      when :cloud, :nabu_casa
        # Use Home Assistant's TTS get_url API
        voice_name = CLOUD_VOICES[voice.to_sym] || voice.to_s

        params = {
          platform: provider_id,
          message: message,
          language: language,
          cache: true
        }

        # Add voice options
        tts_options = {}
        tts_options[:voice] = voice_name
        tts_options[:style] = options[:style] if options[:style]
        tts_options[:speed] = speed if speed && speed != 100

        params[:options] = tts_options unless tts_options.empty?

        # Call HA API to get TTS URL
        response = @home_assistant.post('/api/tts_get_url', params)
        response['url'] || response['path']
      else
        # For other providers, generate through HA and get URL
        raise "Audio file generation not yet implemented for #{provider}"
      end
    end

    def download_audio_file(audio_url, output_path)
      require 'net/http'
      require 'uri'

      # Handle relative URLs from Home Assistant
      if audio_url.start_with?('/')
        base_url = @home_assistant.base_url
        audio_url = "#{base_url}#{audio_url}"
      end

      uri = URI(audio_url)

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https') do |http|
        request = Net::HTTP::Get.new(uri)

        # Add authentication if needed
        request['Authorization'] = "Bearer #{@home_assistant.token}" if @home_assistant.token

        response = http.request(request)

        raise "Failed to download audio: #{response.code} - #{response.body}" unless response.code == '200'

        File.binwrite(output_path, response.body)
      end

      output_path
    end

    def generate_fallback_audio(_message, format)
      # Generate using Google TTS as fallback
      # This is a simplified implementation - in production would use actual Google TTS API
      output_path = generate_temp_audio_path(format)

      begin
        # No Google TTS - we don't have a key
        raise 'Audio file generation requires cloud TTS'

        # Get the cached file path from HA
        # This would need actual implementation based on HA's TTS cache structure
        output_path
      rescue StandardError => e
        puts "⚠️  Fallback audio generation failed: #{e.message}"
        nil
      end
    end
  end
end
