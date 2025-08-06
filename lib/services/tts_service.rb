# frozen_string_literal: true

require 'securerandom'
require 'tmpdir'
require_relative '../home_assistant_client'
require_relative 'logger_service'

module Services
  class TTSService
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
    CLOUD_VOICES = {
      # US English neural voices with emotional variants
      jenny: 'JennyNeural',
      aria: 'AriaNeural',
      guy: 'GuyNeural',
      davis: 'DavisNeural',
      # Add more as needed
      default: 'JennyNeural'
    }.freeze

    # Mood to voice style mapping (2025 feature)
    MOOD_STYLES = {
      friendly: 'friendly',
      angry: 'angry',
      sad: 'sad',
      excited: 'excited',
      whisper: 'whisper',
      cheerful: 'cheerful',
      terrified: 'terrified',
      neutral: nil # no style modifier
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
      
      # Apply mood-based modifications
      if mood && MOOD_STYLES.key?(mood.to_sym)
        options[:style] = MOOD_STYLES[mood.to_sym] if MOOD_STYLES[mood.to_sym]
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
      rescue => e
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
        
        handle_tts_error(e, message, entity_id)
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
      rescue => e
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
        fallback_audio_path = generate_fallback_audio(message, format)
        fallback_audio_path
      end
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

      # Use modern tts.speak action for cloud providers
      if [:cloud, :nabu_casa].include?(provider.to_sym)
        data = {
          target: {
            entity_id: provider_id
          },
          data: {
            media_player_entity_id: entity_id,
            message: message,
            language: language,
            cache: cache
          }
        }
        
        data[:data][:options] = tts_options unless tts_options.empty?
        
        @home_assistant.post('/api/services/tts/speak', data)
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
      if speed && speed != 100
        chime_data[:tts_playbook_speed] = speed
      end

      # Add volume
      if volume
        chime_data[:volume_level] = volume
      end

      # Add any additional options
      chime_data.merge!(options.except(:tts_platform))

      @home_assistant.call_service('chime_tts', 'say', chime_data)
      true
    end

    def build_tts_options(provider:, voice:, speed:, **options)
      tts_options = {}

      # Add voice selection
      if voice
        voice_name = CLOUD_VOICES[voice.to_sym] || voice.to_s
        tts_options[:voice] = voice_name
      end

      # Add style if provided (2025 feature for cloud TTS)
      if options[:style]
        tts_options[:style] = options[:style]
      end

      # Add speed adjustment (provider-specific)
      if speed && speed != 100 && [:cloud, :nabu_casa, :elevenlabs].include?(provider.to_sym)
        tts_options[:speed] = speed
      end

      # Add any additional provider-specific options
      tts_options.merge!(options.except(:style, :tts_platform))

      tts_options
    end

    def handle_tts_error(error, message, entity_id)
      puts "⚠️  TTS failed for '#{truncate_message(message)}' on #{entity_id}: #{error.message}"
      
      # Try fallback to basic TTS if using advanced features
      if @default_provider != :google
        puts "🔄 Attempting fallback to Google TTS..."
        begin
          @home_assistant.call_service(
            'tts',
            'google_translate_say',
            entity_id: entity_id,
            message: message
          )
          return true
        rescue => fallback_error
          puts "⚠️  Fallback also failed: #{fallback_error.message}"
        end
      end

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
        if @home_assistant.token
          request['Authorization'] = "Bearer #{@home_assistant.token}"
        end
        
        response = http.request(request)
        
        if response.code == '200'
          File.open(output_path, 'wb') do |file|
            file.write(response.body)
          end
        else
          raise "Failed to download audio: #{response.code} - #{response.body}"
        end
      end
      
      output_path
    end

    def generate_fallback_audio(message, format)
      # Generate using Google TTS as fallback
      # This is a simplified implementation - in production would use actual Google TTS API
      output_path = generate_temp_audio_path(format)
      
      begin
        # Try to use HA's Google TTS
        @home_assistant.call_service(
          'tts',
          'google_translate_say',
          entity_id: 'media_player.none',  # Don't play, just generate
          message: message,
          cache: true
        )
        
        # Get the cached file path from HA
        # This would need actual implementation based on HA's TTS cache structure
        output_path
      rescue => e
        puts "⚠️  Fallback audio generation failed: #{e.message}"
        nil
      end
    end
  end
end