# frozen_string_literal: true

require_relative '../utils/location_helper'
require_relative '../utils/burning_man_landmarks'
require_relative '../utils/brc_coordinate_service'
require_relative '../cube/settings'

module Services
  class GpsTrackingService
    include Utils::LocationHelper

    def initialize
      @ha_client = ::HomeAssistantClient.new
    end

    # Get current GPS coordinates - tries HA first, then simulation, then random landmark
    def current_location
      # Check for simulation mode first
      if Cube::Settings.simulate_cube_movement?
        sim_location = load_simulation_location
        return sim_location if sim_location
      end

      # Try real GPS from Home Assistant
      device_tracker_entity = begin
        GlitchCube.config.gps.device_tracker_entity
      rescue StandardError
        'device_tracker.glitch_cube'
      end

      begin
        entity_state = @ha_client.states.find { |state| state['entity_id'] == device_tracker_entity }

        if entity_state && entity_state['attributes']
          lat = entity_state['attributes']['latitude']&.to_f
          lng = entity_state['attributes']['longitude']&.to_f

          if lat && lng
            return {
              lat: lat,
              lng: lng,
              timestamp: Time.parse(entity_state['last_updated']),
              accuracy: entity_state['attributes']['gps_accuracy'],
              battery: entity_state['attributes']['battery_level'],
              address: brc_address_from_coordinates(lat, lng),
              # Flatten context/distance hash if returned by location_context
              **(ctx = location_context(lat, lng)).is_a?(Hash) ? ctx : { context: ctx },
              source: 'gps'
            }
          end
        end
      rescue StandardError
        # GPS unavailable - will use random landmark
      end

      # No GPS available - pick random landmark
      random_landmark_location
    end

    # Convert GPS coordinates to Burning Man address format
    def brc_address_from_coordinates(lat, lng)
      Utils::BrcCoordinateService.brc_address_from_coordinates(lat, lng)
    end

    # Get contextual location description with proximity detection
    def location_context(lat, lng)
      nearby_landmarks = detect_nearby_landmarks(lat, lng)
      brc_area = Utils::BrcCoordinateService.brc_address_from_coordinates(lat, lng)
      the_man = Utils::BrcCoordinateService.golden_spike_coordinates
      distance = Utils::BrcCoordinateService.distance_between_points(the_man[:lat], the_man[:lng], lat, lng)
      distance_str = "#{format('%.2f', distance)} mi from The Man"

      # Section logic: classify area into "In The City", "Inner Playa", etc.
      section =
        if brc_area.include?('Esplanade') || brc_area =~ /\d{1,2}:\d{2}/
          'In The City'
        elsif brc_area.include?('Inner Playa')
          'Inner Playa'
        elsif brc_area.include?('Outer Playa')
          'Outer Playa'
        elsif brc_area.include?('Deep Playa')
          'Deep Playa'
        else
          'Unknown Area'
        end

      if nearby_landmarks.any?
        context = nearby_landmarks.first[:context]
        landmark_name = nearby_landmarks.first[:name]
        {
          context: context,
          landmark_name: landmark_name,
          brc_area: brc_area,
          section: section,
          distance_from_man: distance_str
        }
      else
        {
          context: '',
          landmark_name: nil,
          brc_area: brc_area,
          section: section,
          distance_from_man: distance_str
        }
      end
    end

    # Detect nearby landmarks and return proximity info
    def detect_nearby_landmarks(lat, lng)
      require_relative '../utils/geo_constants'

      all_nearby = []

      # Only show major landmarks: plazas, center camp, rods road, the man, big landmarks
      # Skip toilets/portos since they're funny but not needed
      landmark_queries = {
        'center' => Utils::GeoConstants::PROXIMITY_DISTANCES[:camps],     # Center Camp, The Man
        'sacred' => Utils::GeoConstants::PROXIMITY_DISTANCES[:camps],     # Temple
        'plaza' => Utils::GeoConstants::PROXIMITY_DISTANCES[:camps],      # Plazas
        'service' => Utils::GeoConstants::PROXIMITY_DISTANCES[:services], # Rods Road
        'art' => Utils::GeoConstants::PROXIMITY_DISTANCES[:art]           # Big art installations
      }

      # Query each landmark type with its appropriate radius
      landmark_queries.each do |type, radius|
        type_landmarks = Landmark.active
                                 .where(landmark_type: type)
                                 .near_location(lat, lng, radius)

        type_landmarks.each do |landmark|
          distance = landmark.distance_from(lat, lng)
          all_nearby << {
            name: landmark.name,
            type: landmark.landmark_type,
            distance: distance,
            context: landmark.description || "Near #{landmark.name}"
          }
        end
      end

      # Get any other landmark types with default proximity (25 feet)
      other_types = Landmark.active
                            .where.not(landmark_type: landmark_queries.keys)
                            .near_location(lat, lng, Utils::GeoConstants::PROXIMITY_DISTANCES[:landmarks])

      other_types.each do |landmark|
        distance = landmark.distance_from(lat, lng)
        all_nearby << {
          name: landmark.name,
          type: landmark.landmark_type,
          distance: distance,
          context: landmark.description || "Near #{landmark.name}"
        }
      end

      # Sort by distance and remove duplicates
      all_nearby.uniq { |l| l[:name] }.sort_by { |l| l[:distance] }
    end

    # Get proximity data for map reactions
    def proximity_data(lat, lng)
      nearby_landmarks = detect_nearby_landmarks(lat, lng)

      # Check porto clusters
      nearby_portos = detect_nearby_portos(lat, lng)

      {
        landmarks: nearby_landmarks,
        portos: nearby_portos,
        map_mode: determine_map_mode(nearby_landmarks),
        visual_effects: determine_visual_effects(nearby_landmarks)
      }
    end

    private

    def load_simulation_location
      require 'redis'
      redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0')
      coords_json = redis.get('current_cube_location')
      return nil unless coords_json

      coords = JSON.parse(coords_json)
      lat = coords['lat']
      lng = coords['lng']

      {
        lat: lat,
        lng: lng,
        timestamp: begin
          Time.parse(coords['timestamp'])
        rescue StandardError
          Time.now
        end,
        accuracy: nil,
        battery: nil,
        address: coords['address'], # Use cached address from Redis
        # Recompute context/distance for simulation
        **(ctx = location_context(lat, lng)).is_a?(Hash) ? ctx : { context: ctx },
        destination: coords['destination'], # Include destination for movement info
        source: 'simulation'
      }
    rescue StandardError => e
      Services::LoggerService.log_api_call(
        service: 'GPS Tracking',
        endpoint: 'load_simulation_location',
        error: "Error reading simulation from Redis: #{e.message}",
        success: false
      )
      nil
    end

    def random_landmark_location
      # Pick a random landmark from database
      landmark = Landmark.active.order('RANDOM()').first
      lat = landmark.latitude.to_f
      lng = landmark.longitude.to_f

      {
        lat: lat,
        lng: lng,
        timestamp: Time.now,
        accuracy: nil,
        battery: nil,
        address: brc_address_from_coordinates(lat, lng),
        **(ctx = location_context(lat, lng)).is_a?(Hash) ? ctx : { context: ctx },
        source: 'random_location'
      }
    end

    # Detect nearby porto clusters using spatial database queries
    def detect_nearby_portos(lat, lng)
      # Use spatial query for toilet landmarks
      toilet_landmarks = Landmark.active
                                 .where(landmark_type: 'toilet')
                                 .near_location(lat, lng, Utils::GeoConstants::PROXIMITY_DISTANCES[:toilets])

      nearby_portos = toilet_landmarks.map do |toilet|
        {
          name: toilet.name,
          distance: toilet.distance_from(lat, lng),
          type: 'toilet'
        }
      end

      # Sort by distance
      nearby_portos.sort_by { |p| p[:distance] }
    end

    # Determine map visual mode based on proximity
    def determine_map_mode(nearby_landmarks)
      return 'normal' if nearby_landmarks.empty?

      primary_landmark = nearby_landmarks.first
      case primary_landmark[:type]
      when 'sacred'
        'temple' # Desaturated, reverent colors
      when 'center'
        'man' # Bright, energetic colors
      when 'medical'
        'emergency' # Red highlights, clear navigation
      when 'service'
        'service' # Blue highlights for utilities
      else
        'landmark' # Enhanced visibility
      end
    end

    # Determine visual effects for map display
    def determine_visual_effects(nearby_landmarks)
      effects = []

      nearby_landmarks.each do |landmark|
        case landmark[:type]
        when 'sacred'
          effects << {
            type: 'aura',
            color: 'white',
            intensity: 'soft',
            description: 'Sacred space - respectful proximity'
          }
        when 'center'
          effects << {
            type: 'pulse',
            color: 'orange',
            intensity: 'strong',
            description: 'Center of the burn - high energy'
          }
        when 'medical'
          effects << {
            type: 'beacon',
            color: 'red',
            intensity: 'steady',
            description: 'Emergency services nearby'
          }
        when 'service'
          effects << {
            type: 'glow',
            color: 'blue',
            intensity: 'medium',
            description: 'Services available'
          }
        end
      end

      effects
    end
  end
end
