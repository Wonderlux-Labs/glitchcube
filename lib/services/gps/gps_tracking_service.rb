# frozen_string_literal: true

# Simple service to get GPS coordinates from Home Assistant
# All location context comes from LocationContextService
module Services
  class GpsTrackingService
    def initialize
      @ha_client = ::HomeAssistantClient.new
    end

    # Get current GPS coordinates with full location context
    def current_location
      # Check for spoofed GPS first (development only), then Home Assistant, then fallback
      coords = fetch_spoofed_location || fetch_from_home_assistant || random_landmark_location

      # Get full context from LocationContextService (this is cached)
      context = Services::LocationContextService.full_context(coords[:lat], coords[:lng])

      # Merge GPS metadata with location context
      coords.merge(context)
    end

    # DEPRECATED - just use LocationContextService.full_context instead
    def brc_address_from_coordinates(lat, lng)
      Services::LocationContextService.full_context(lat, lng)[:address]
    end

    # Get proximity data for map reactions using LocationContextService
    def proximity_data(lat, lng)
      context = Services::LocationContextService.full_context(lat, lng)
      landmarks = context[:landmarks] || []

      {
        landmarks: landmarks,
        portos: context[:nearest_porto] ? [context[:nearest_porto]] : [],
        map_mode: determine_map_mode_from_landmarks(landmarks),
        visual_effects: determine_visual_effects_from_landmarks(landmarks)
      }
    end

    private

    def fetch_spoofed_location
      # Only allow spoofed locations in development
      return nil unless ENV['RACK_ENV'] == 'development'

      begin
        redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0')
        spoofed_data = redis.get('current_cube_location')
        return nil unless spoofed_data

        data = JSON.parse(spoofed_data, symbolize_names: true)
        {
          lat: data[:lat],
          lng: data[:lng],
          timestamp: Time.parse(data[:timestamp]),
          accuracy: nil,
          battery: nil,
          source: 'spoofed'
        }
      rescue StandardError
        nil
      end
    end

    def determine_map_mode_from_landmarks(landmarks)
      return 'normal' if landmarks.empty?

      primary = landmarks.first
      case primary[:type]
      when 'sacred' then 'temple'
      when 'center' then 'man'
      when 'medical' then 'emergency'
      when 'service' then 'service'
      else 'landmark'
      end
    end

    def determine_visual_effects_from_landmarks(landmarks)
      effects = []

      landmarks.each do |landmark|
        case landmark[:type]
        when 'sacred'
          effects << { type: 'aura', color: 'white', intensity: 'soft' }
        when 'center'
          effects << { type: 'pulse', color: 'orange', intensity: 'strong' }
        when 'medical'
          effects << { type: 'beacon', color: 'red', intensity: 'steady' }
        when 'service'
          effects << { type: 'glow', color: 'blue', intensity: 'medium' }
        end
      end

      effects
    end

    def fetch_from_home_assistant
      device_tracker_entity = begin
        GlitchCube.config.gps.device_tracker_entity
      rescue StandardError
        'device_tracker.glitch_cube'
      end

      entity_state = @ha_client.states.find { |state| state['entity_id'] == device_tracker_entity }
      return nil unless entity_state && entity_state['attributes']

      lat = entity_state['attributes']['latitude']&.to_f
      lng = entity_state['attributes']['longitude']&.to_f
      return nil unless lat && lng

      {
        lat: lat,
        lng: lng,
        timestamp: Time.parse(entity_state['last_updated']),
        accuracy: entity_state['attributes']['gps_accuracy'],
        battery: entity_state['attributes']['battery_level'],
        source: 'gps'
      }
    rescue StandardError
      nil
    end

    def random_landmark_location
      landmark = Landmark.active.order('RANDOM()').first

      {
        lat: landmark.latitude.to_f,
        lng: landmark.longitude.to_f,
        timestamp: Time.now,
        accuracy: nil,
        battery: nil,
        source: 'random_landmark'
      }
    end
  end
end
