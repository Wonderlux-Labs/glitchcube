# frozen_string_literal: true

require_relative 'base_tool'
require_relative '../services/logger_service'

# Tool for controlling Music Assistant and media playback
# Provides music control, playlist management, and audio routing
class MusicTool < BaseTool
  def self.name
    'music_control'
  end

  def self.description
    'Control Music Assistant for audio playbook and music management on the Glitch Cube. Supports search, playback control, and status queries.'
  end

  def self.category
    'media_control'
  end

  def self.tool_prompt
    'Search local library and Spotify with search_music(). Play tracks with play_media(). Control with pause_media(), stop_media(), next_track(), set_volume().'
  end

  # Search for music in Music Assistant
  def self.search_music(query:, limit: 5)
    return format_response(false, 'Query is required for music search') if query.nil? || query.empty?

    begin
      # Use the actual Music Assistant config entry ID from Home Assistant
      result = call_ha_service('music_assistant', 'search', {
                                 name: query,
                                 limit: limit,
                                 config_entry_id: '01K1VK4MYJ75WNGJR5ESSAC2WY' # Music Assistant instance ID
                               }, return_response: true)

      Services::LoggerService.log_api_call(
        service: 'music_tool',
        endpoint: 'search',
        query: query,
        limit: limit
      )

      # Format the search results nicely
      if result && result['service_response']
        format_search_results(result['service_response'], query)
      else
        "No results found for '#{query}'"
      end
    rescue StandardError => e
      "❌ Music search error: #{e.message}"
    end
  end

  # Format search results for display
  def self.format_search_results(response, query)
    results = []
    results << "=== SEARCH RESULTS FOR '#{query}' ==="

    # Handle different result types (artists, albums, tracks, playlists)
    %w[artists albums tracks playlists].each do |type|
      next unless response[type] && !response[type].empty?

      results << "\n#{type.capitalize}:"
      response[type].each_with_index do |item, idx|
        # Format based on type
        case type
        when 'artists'
          results << "  #{idx + 1}. #{item['name']} (URI: #{item['uri']})"
        when 'albums'
          artist = item['artists']&.first&.dig('name') || 'Unknown Artist'
          results << "  #{idx + 1}. #{item['name']} by #{artist} (URI: #{item['uri']})"
        when 'tracks'
          artist = item['artists']&.first&.dig('name') || 'Unknown Artist'
          album = item['album']&.dig('name') || 'Unknown Album'
          results << "  #{idx + 1}. #{item['name']} - #{artist} (#{album}) (URI: #{item['uri']})"
        when 'playlists'
          results << "  #{idx + 1}. #{item['name']} (URI: #{item['uri']})"
        end
      end
    end

    results << "\nUse the URI to play specific content"
    results.join("\n")
  end

  # List all available media players with their capabilities
  def self.list_available_players(verbose: true)
    result = []
    result << '=== AVAILABLE MEDIA PLAYERS ==='

    begin
      # Get all media_player entities from Home Assistant
      states = ha_client.states
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
        # rubocop:enable Metrics/BlockLength

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

  # Play media on the Glitch Cube music player
  def self.play_media(track:, volume: nil, mode: 'add')
    player = 'cube_music' # Hardcoded - art installation has fixed audio setup

    return format_response(false, 'Track is required') if track.nil? || track.empty?

    entity_id = resolve_player_entity(player)
    return "Error: Player '#{player}' not found" unless entity_id

    begin
      # Set volume if specified
      if volume
        volume_float = volume.is_a?(String) ? volume.to_f : volume
        call_ha_service('media_player', 'volume_set', {
                          entity_id: entity_id,
                          volume_level: volume_float
                        })
      end

      # Play the track using Music Assistant's play_media service
      # This will do fuzzy search and play first result if not an exact ID
      enqueue_mode = mode == 'replace_next' ? 'replace_next' : 'add'

      call_ha_service('music_assistant', 'play_media', {
                        media_id: track,
                        media_type: 'track', # Can be track, album, artist, playlist
                        enqueue: enqueue_mode,
                        entity_id: entity_id
                      })

      # Ensure playback is started (queuing doesn't auto-start)
      sleep(0.5) # Brief pause to let the queue update
      call_ha_service('media_player', 'media_play', {
                        entity_id: entity_id
                      })

      Services::LoggerService.log_api_call(
        service: 'music_tool',
        endpoint: 'play',
        entity_id: entity_id,
        track: track,
        volume: volume,
        mode: enqueue_mode
      )

      volume_desc = volume ? " at #{(volume.to_f * 100).round}% volume" : ''
      mode_desc = mode == 'replace_next' ? ' (replaced queue)' : ' (added to queue)'
      format_response(true, "Playing '#{track}' on #{player}#{volume_desc}#{mode_desc}")
    rescue StandardError => e
      format_response(false, "Failed to play on #{player}: #{e.message}")
    end
  end

  # Pause media player
  def self.pause_media
    player = 'cube_music' # Hardcoded - art installation has fixed audio setup

    entity_id = resolve_player_entity(player)
    return format_response(false, "Player '#{player}' not found") unless entity_id

    begin
      call_ha_service('media_player', 'media_pause', { entity_id: entity_id })
      format_response(true, 'Paused Glitch Cube music')
    rescue StandardError => e
      format_response(false, "Failed to pause music: #{e.message}")
    end
  end

  # Stop media player
  def self.stop_media
    player = 'cube_music' # Hardcoded - art installation has fixed audio setup

    entity_id = resolve_player_entity(player)
    return format_response(false, "Player '#{player}' not found") unless entity_id

    begin
      call_ha_service('media_player', 'media_stop', { entity_id: entity_id })
      format_response(true, 'Stopped Glitch Cube music')
    rescue StandardError => e
      format_response(false, "Failed to stop music: #{e.message}")
    end
  end

  # Set volume for media player
  def self.set_volume(volume:)
    player = 'cube_music' # Hardcoded - art installation has fixed audio setup

    return format_response(false, 'Volume is required') if volume.nil?

    entity_id = resolve_player_entity(player)
    return format_response(false, "Player '#{player}' not found") unless entity_id

    # Convert volume to float between 0.0 and 1.0
    volume_level = volume.is_a?(String) ? volume.to_f : volume
    volume_level /= 100.0 if volume_level > 1.0 # Convert percentage to decimal
    volume_level = [[0.0, volume_level].max, 1.0].min # Clamp between 0.0 and 1.0

    begin
      call_ha_service('media_player', 'volume_set', {
                        entity_id: entity_id,
                        volume_level: volume_level
                      })

      format_response(true, "Set Glitch Cube music volume to #{(volume_level * 100).round}%")
    rescue StandardError => e
      format_response(false, "Failed to set music volume: #{e.message}")
    end
  end

  # Skip to next track
  def self.next_track
    player = 'cube_music' # Hardcoded - art installation has fixed audio setup

    entity_id = resolve_player_entity(player)
    return format_response(false, "Player '#{player}' not found") unless entity_id

    begin
      call_ha_service('media_player', 'media_next_track', { entity_id: entity_id })
      format_response(true, 'Skipped to next track')
    rescue StandardError => e
      format_response(false, "Failed to skip track: #{e.message}")
    end
  end

  # Skip to previous track
  def self.previous_track
    player = 'cube_music' # Hardcoded - art installation has fixed audio setup

    entity_id = resolve_player_entity(player)
    return format_response(false, "Player '#{player}' not found") unless entity_id

    begin
      call_ha_service('media_player', 'media_previous_track', { entity_id: entity_id })
      format_response(true, 'Skipped to previous track')
    rescue StandardError => e
      format_response(false, "Failed to skip to previous track: #{e.message}")
    end
  end

  # Get detailed status of media player
  def self.get_player_status
    player = 'cube_music' # Hardcoded - art installation has fixed audio setup

    entity_id = resolve_player_entity(player)
    return format_response(false, "Player '#{player}' not found") unless entity_id

    begin
      state = ha_client.state(entity_id)

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
        'Glitch Cube music: unavailable'
      end
    rescue StandardError => e
      format_response(false, "Error getting music status: #{e.message}")
    end
  end

  # Resolve player name to full entity ID
  def self.resolve_player_entity(player_name)
    return player_name if player_name.start_with?('media_player.')

    # Try to find the entity by name
    states = ha_client.states
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
