# frozen_string_literal: true

require_relative 'base_tool'
require_relative '../services/logger_service'

# Tool for text-to-speech synthesis through Home Assistant
# Provides speech output for conversation responses and notifications
class SpeechTool < BaseTool
  def self.name
    'speech_synthesis'
  end

  def self.description
    'Convert text to speech using Home Assistant TTS services. Supports multiple TTS engines and voice configuration.'
  end

  def self.category
    'audio_interface'
  end

  def self.tool_prompt
    'Speak text using speak_text(). Configure voice with set_voice(). Check available voices with list_voices().'
  end

  # Default TTS entity for the Glitch Cube
  DEFAULT_ENTITY = 'media_player.square_voice'

  # Speak text using Home Assistant TTS
  def self.speak_text(text:, entity_id: DEFAULT_ENTITY, language: 'en-US', voice: nil)
    return format_response(false, 'Text is required for speech synthesis') if text.nil? || text.strip.empty?

    begin
      start_time = Time.now

      # Prepare options for TTS call
      options = { entity_id: entity_id }
      options[:language] = language if language
      options[:voice] = voice if voice

      # Use Home Assistant client for TTS
      success = ha_client.speak(text, **options)

      duration_ms = ((Time.now - start_time) * 1000).round

      # Log the TTS call
      Services::LoggerService.log_tts(
        message: text,
        success: success,
        duration: duration_ms,
        entity_id: entity_id,
        language: language,
        voice: voice
      )

      if success
        voice_desc = voice ? " using voice '#{voice}'" : ''
        lang_desc = language == 'en-US' ? '' : " in #{language}"
        entity_desc = entity_id == DEFAULT_ENTITY ? '' : " on #{entity_id}"

        "Spoke: '#{text.length > 50 ? "#{text[0..47]}..." : text}'#{voice_desc}#{lang_desc}#{entity_desc}"
      else
        'Failed to synthesize speech'
      end
    rescue StandardError => e
      duration_ms = ((Time.now - start_time) * 1000).round if defined?(start_time)

      # Log the error
      Services::LoggerService.log_tts(
        message: text,
        success: false,
        duration: duration_ms || 0,
        error: e.message,
        entity_id: entity_id
      )

      "Failed to speak text: #{e.message}"
    end
  end

  # List available TTS voices and languages
  def self.list_voices(verbose: false)
    result = []
    result << '=== AVAILABLE TTS VOICES ==='

    begin
      # Get TTS service configuration from Home Assistant
      services = ha_client.get_services || {}
      tts_services = services.slice('tts')

      if tts_services.empty?
        result << 'No TTS services available'
        return result.join("\n")
      end

      tts_services.each do |domain, service_info|
        service_info.each do |service_name, service_details|
          result << "Service: #{domain}.#{service_name}"

          next unless verbose && service_details['fields']

          # Show available parameters
          fields = service_details['fields']

          if fields['language'] && fields['language']['values']
            languages = fields['language']['values'].keys
            result << "  Languages: #{languages.join(', ')}"
          end

          if fields['voice'] && fields['voice']['values']
            voices = fields['voice']['values'].keys
            result << "  Voices: #{voices.join(', ')}"
          end

          result << "  Description: #{service_details['description']}" if service_details['description']
        end
      end

      # Show available media players that can play TTS
      result << ''
      result << '=== AVAILABLE MEDIA PLAYERS ==='

      states = ha_client.states || []
      media_players = states.select { |state| state['entity_id'].start_with?('media_player.') }

      available_players = []
      media_players.each do |player|
        next if player['state'] == 'unavailable'

        entity_id = player['entity_id']
        friendly_name = player.dig('attributes', 'friendly_name') || entity_id
        available_players << "#{entity_id} (#{friendly_name})"
      end

      result << available_players.join("\n  ")
    rescue StandardError => e
      result << "Error listing TTS voices: #{e.message}"
    end

    result.join("\n")
  end

  # Set default voice for subsequent TTS calls (placeholder for future enhancement)
  def self.set_voice(voice:, language: 'en-US')
    # This could be expanded to store voice preferences in configuration
    # For now, just validate the voice exists

    voices_info = list_voices(verbose: true)

    if voices_info.include?(voice)
      "Set default voice to '#{voice}' for language '#{language}'"
    else
      "Voice '#{voice}' not found. Available voices:\n#{voices_info}"
    end
  rescue StandardError => e
    "Failed to set voice: #{e.message}"
  end

  # Get current TTS status and configuration
  def self.get_tts_status(entity_id: DEFAULT_ENTITY)
    # Get media player state
    state = ha_client.state(entity_id)

    if state && state['state'] != 'unavailable'
      result = []
      result << "TTS Entity: #{entity_id}"
      result << "State: #{state['state']}"

      # Media info
      media_title = state.dig('attributes', 'media_title')
      result << "Playing: #{media_title}" if media_title

      # Volume
      volume = state.dig('attributes', 'volume_level')
      result << "Volume: #{(volume * 100).round}%" if volume

      # Device info
      friendly_name = state.dig('attributes', 'friendly_name')
      result << "Device: #{friendly_name}" if friendly_name && friendly_name != entity_id

      result.join(' | ')
    else
      "TTS entity #{entity_id} is unavailable"
    end
  rescue StandardError => e
    "Error getting TTS status: #{e.message}"
  end

  # Quick announcement method for system messages
  def self.announce(message:, priority: 'normal')
    case priority
    when 'high'
    when 'low'
    end
    entity = DEFAULT_ENTITY

    speak_text(text: message, entity_id: entity)
  rescue StandardError => e
    "Failed to make announcement: #{e.message}"
  end
end
