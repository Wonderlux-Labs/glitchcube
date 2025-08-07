# frozen_string_literal: true

require_relative '../home_assistant_client'
require_relative '../services/logger_service'

# Tool for controlling Music Assistant and media playback
# Provides music control, playlist management, and audio routing
class MusicTool
  def self.name
    'music_control'
  end

  def self.description
    'Control Music Assistant for audio playback and music management. Actions: "list_players" (verbose: true/false - shows available media players), "play" (player, source, volume), "pause" (player), "stop" (player), "set_volume" (player, volume), "next_track" (player), "previous_track" (player), "get_status" (player). Players and sources discovered dynamically. Args: action (string), params (string) - JSON with player, source, volume, etc.'
  end

  def self.call(action:, params: '{}')
    params = JSON.parse(params) if params.is_a?(String)

    client = HomeAssistantClient.new

    case action
    when 'list_players'
      list_available_players(client, params)
    when 'play'
      play_media(client, params)
    when 'pause'
      pause_media(client, params)
    when 'stop'
      stop_media(client, params)
    when 'set_volume'
      set_volume(client, params)
    when 'next_track'
      next_track(client, params)
    when 'previous_track'
      previous_track(client, params)
    when 'get_status'
      get_player_status(client, params)
    else
      "Unknown action: #{action}. Available actions: list_players, play, pause, stop, set_volume, next_track, previous_track, get_status"
    end
  rescue StandardError => e
    "Music control error: #{e.message}"
  end

  # List all available media players with their capabilities
  def self.list_available_players(client, params)
    verbose = params['verbose'] != false # Default to verbose unless explicitly false

    result = []
    result << '=== AVAILABLE MEDIA PLAYERS ==='

    begin
      # Get all media_player entities from Home Assistant
      states = client.states
      media_players = states.select { |state| state['entity_id'].start_with?('media_player.') }

      if verbose
        media_players.each do |player|
          entity_id = player['entity_id']
          player_name = entity_id.split('.').last

          if player['state'] == 'unavailable'
            result << "  ❌ #{player_name} (#{entity_id}): unavailable"
          else
            friendly_name = player.dig('attributes', 'friendly_name')
            supported_features = player.dig('attributes', 'supported_features') || 0
            volume_level = player.dig('attributes', 'volume_level')
            media_title = player.dig('attributes', 'media_title')
            media_artist = player.dig('attributes', 'media_artist')

            player_info = "#{player_name} (#{entity_id}): #{player['state']}"
            player_info += " - #{friendly_name}" if friendly_name && friendly_name != entity_id
            player_info += " | Volume: #{(volume_level * 100).round}%" if volume_level

            # Show currently playing media
            if media_title || media_artist
              current_media = [media_artist, media_title].compact.join(' - ')
              player_info += " | Playing: #{current_media}"
            end

            # Decode supported features (Home Assistant media player feature flags)
            features = []
            features << 'play/pause' if supported_features.anybits?(1) # SUPPORT_PAUSE
            features << 'volume' if supported_features.anybits?(4)     # SUPPORT_VOLUME_SET
            features << 'seek' if supported_features.anybits?(8)       # SUPPORT_SEEK
            features << 'next/prev' if supported_features.anybits?(16) # SUPPORT_NEXT_TRACK
            features << 'turn_on/off' if supported_features.anybits?(128) # SUPPORT_TURN_ON

            player_info += " | Features: #{features.join(', ')}" if features.any?

            result << "  ✅ #{player_info}"
          end
        end

        result << ''
        result << '=== USAGE EXAMPLES ==='
        result << 'Play media: {"action": "play", "params": {"player": "tablet", "source": "Spotify", "volume": 0.7}}'
        result << 'Set volume: {"action": "set_volume", "params": {"player": "tablet", "volume": 0.5}}'
        result << 'Get status: {"action": "get_status", "params": {"player": "tablet"}}'

      else
        # Simple list
        available_players = []
        media_players.each do |player|
          if player['state'] != 'unavailable'
            player_name = player['entity_id'].split('.').last
            available_players << player_name
          end
        end

        result << "Available: #{available_players.join(', ')}"
        result << 'Use verbose: true for detailed capabilities'
      end

      Services::LoggerService.log_api_call(
        service: 'music_tool',
        endpoint: 'list_players',
        verbose: verbose,
        player_count: media_players.size
      )

      result.join("\n")
    rescue StandardError => e
      "Error listing media players: #{e.message}"
    end
  end

  # Play media on specified player
  def self.play_media(client, params)
    player = params['player']
    source = params['source']
    volume = params['volume']

    return 'Error: player required' unless player

    entity_id = resolve_player_entity(client, player)
    return "Error: Player '#{player}' not found" unless entity_id

    begin
      # Set volume if specified
      if volume
        volume_float = volume.is_a?(String) ? volume.to_f : volume
        client.call_service('media_player', 'volume_set', {
                              entity_id: entity_id,
                              volume_level: volume_float
                            })
      end

      # If source is provided, try to play it
      if source
        # For Music Assistant, we might need to browse media or use specific service calls
        # For now, try generic media_player.play_media
        client.call_service('media_player', 'play_media', {
                              entity_id: entity_id,
                              media_content_type: 'music',
                              media_content_id: source
                            })
      else
        # Just resume/play current media
        client.call_service('media_player', 'media_play', {
                              entity_id: entity_id
                            })
      end

      Services::LoggerService.log_api_call(
        service: 'music_tool',
        endpoint: 'play',
        entity_id: entity_id,
        source: source,
        volume: volume
      )

      source_desc = source ? " (#{source})" : ''
      volume_desc = volume ? " at #{(volume.to_f * 100).round}% volume" : ''
      "Started playback on #{player}#{source_desc}#{volume_desc}"
    rescue StandardError => e
      "Failed to play on #{player}: #{e.message}"
    end
  end

  # Pause media player
  def self.pause_media(client, params)
    player = params['player']
    return 'Error: player required' unless player

    entity_id = resolve_player_entity(client, player)
    return "Error: Player '#{player}' not found" unless entity_id

    begin
      client.call_service('media_player', 'media_pause', { entity_id: entity_id })
      "Paused #{player}"
    rescue StandardError => e
      "Failed to pause #{player}: #{e.message}"
    end
  end

  # Stop media player
  def self.stop_media(client, params)
    player = params['player']
    return 'Error: player required' unless player

    entity_id = resolve_player_entity(client, player)
    return "Error: Player '#{player}' not found" unless entity_id

    begin
      client.call_service('media_player', 'media_stop', { entity_id: entity_id })
      "Stopped #{player}"
    rescue StandardError => e
      "Failed to stop #{player}: #{e.message}"
    end
  end

  # Set volume for media player
  def self.set_volume(client, params)
    player = params['player']
    volume = params['volume']

    return 'Error: player and volume required' unless player && volume

    entity_id = resolve_player_entity(client, player)
    return "Error: Player '#{player}' not found" unless entity_id

    # Convert volume to float between 0.0 and 1.0
    volume_level = volume.is_a?(String) ? volume.to_f : volume
    volume_level /= 100.0 if volume_level > 1.0 # Convert percentage to decimal
    volume_level = [[0.0, volume_level].max, 1.0].min # Clamp between 0.0 and 1.0

    begin
      client.call_service('media_player', 'volume_set', {
                            entity_id: entity_id,
                            volume_level: volume_level
                          })

      "Set #{player} volume to #{(volume_level * 100).round}%"
    rescue StandardError => e
      "Failed to set #{player} volume: #{e.message}"
    end
  end

  # Skip to next track
  def self.next_track(client, params)
    player = params['player']
    return 'Error: player required' unless player

    entity_id = resolve_player_entity(client, player)
    return "Error: Player '#{player}' not found" unless entity_id

    begin
      client.call_service('media_player', 'media_next_track', { entity_id: entity_id })
      "Skipped to next track on #{player}"
    rescue StandardError => e
      "Failed to skip track on #{player}: #{e.message}"
    end
  end

  # Skip to previous track
  def self.previous_track(client, params)
    player = params['player']
    return 'Error: player required' unless player

    entity_id = resolve_player_entity(client, player)
    return "Error: Player '#{player}' not found" unless entity_id

    begin
      client.call_service('media_player', 'media_previous_track', { entity_id: entity_id })
      "Skipped to previous track on #{player}"
    rescue StandardError => e
      "Failed to skip to previous track on #{player}: #{e.message}"
    end
  end

  # Get detailed status of media player
  def self.get_player_status(client, params)
    player = params['player']
    return 'Error: player required' unless player

    entity_id = resolve_player_entity(client, player)
    return "Error: Player '#{player}' not found" unless entity_id

    begin
      state = client.state(entity_id)

      if state && state['state'] != 'unavailable'
        status_parts = ["#{player}: #{state['state']}"]

        # Current media info
        media_title = state.dig('attributes', 'media_title')
        media_artist = state.dig('attributes', 'media_artist')
        media_album = state.dig('attributes', 'media_album')

        if media_title || media_artist
          current_media = [media_artist, media_title, media_album].compact.join(' - ')
          status_parts << "Playing: #{current_media}"
        end

        # Volume and position
        volume_level = state.dig('attributes', 'volume_level')
        media_duration = state.dig('attributes', 'media_duration')
        media_position = state.dig('attributes', 'media_position')

        status_parts << "Volume: #{(volume_level * 100).round}%" if volume_level

        if media_duration && media_position
          duration_str = format_duration(media_duration)
          position_str = format_duration(media_position)
          status_parts << "Position: #{position_str} / #{duration_str}"
        end

        status_parts.join(' | ')
      else
        "#{player}: unavailable"
      end
    rescue StandardError => e
      "Error getting #{player} status: #{e.message}"
    end
  end

  # Resolve player name to full entity ID
  def self.resolve_player_entity(client, player_name)
    return player_name if player_name.start_with?('media_player.')

    # Try to find the entity by name
    states = client.states
    media_players = states.select { |state| state['entity_id'].start_with?('media_player.') }

    # Look for exact match first
    exact_match = media_players.find do |p|
      p['entity_id'] == "media_player.#{player_name}" ||
        p.dig('attributes', 'friendly_name')&.downcase == player_name.downcase
    end

    return exact_match['entity_id'] if exact_match

    # Look for partial match
    partial_match = media_players.find do |p|
      p['entity_id'].include?(player_name) ||
        p.dig('attributes', 'friendly_name')&.downcase&.include?(player_name.downcase)
    end

    partial_match&.dig('entity_id')
  rescue StandardError
    nil
  end

  # Format duration in seconds to MM:SS
  def self.format_duration(seconds)
    return '0:00' unless seconds

    minutes = (seconds / 60).floor
    secs = (seconds % 60).floor

    "#{minutes}:#{secs.to_s.rjust(2, '0')}"
  end
end
