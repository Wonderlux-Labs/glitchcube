# frozen_string_literal: true

require_relative '../utils/location_helper'

module Services
  class GpsTrackingService
    include Utils::LocationHelper

    def initialize
      @ha_client = Services::HomeAssistantClient.new
    end

    # Get current GPS coordinates from Home Assistant device tracker
    def current_location
      # GPS configuration with fallback
      begin
        device_tracker_entity = GlitchCube.config.gps.device_tracker_entity
      rescue
        device_tracker_entity = ENV.fetch('GPS_DEVICE_TRACKER_ENTITY', 'device_tracker.glitch_cube')
      end
      
      begin
        entity_state = @ha_client.states.find { |state| state['entity_id'] == device_tracker_entity }
        
        if entity_state && entity_state['attributes']
          lat = entity_state['attributes']['latitude']&.to_f
          lng = entity_state['attributes']['longitude']&.to_f
          
          if lat && lng
            {
              lat: lat,
              lng: lng,
              timestamp: Time.parse(entity_state['last_updated']),
              accuracy: entity_state['attributes']['gps_accuracy'],
              battery: entity_state['attributes']['battery_level'],
              address: brc_address_from_coordinates(lat, lng),
              context: location_context(lat, lng)
            }
          else
            fallback_location
          end
        else
          fallback_location
        end
      rescue => e
        Services::LoggerService.log_api_call(
          service: 'GPS Tracking',
          endpoint: 'current_location',
          error: e.message,
          success: false
        )
        fallback_location
      end
    end

    # Convert GPS coordinates to Burning Man address format
    def brc_address_from_coordinates(lat, lng)
      # Distance from center camp (Golden Spike: 40.786958, -119.202994)
      center_lat = 40.786958
      center_lng = -119.202994
      
      distance = distance_from(lat, lng)
      
      # Determine radial street (time-based)
      bearing = calculate_bearing(center_lat, center_lng, lat, lng)
      radial_street = bearing_to_time_street(bearing)
      
      # Determine concentric street (lettered/named)
      concentric_street = distance_to_concentric_street(distance)
      
      if radial_street && concentric_street
        "#{radial_street} & #{concentric_street}"
      else
        "GPS: #{lat.round(4)}, #{lng.round(4)}"
      end
    end

    # Get contextual location description with proximity detection
    def location_context(lat, lng)
      nearby_landmarks = detect_nearby_landmarks(lat, lng)
      return nearby_landmarks.first[:context] if nearby_landmarks.any?

      center_distance = distance_from(lat, lng)
      
      case center_distance
      when 0..0.5
        "Center Camp"
      when 0.5..1.0
        "Inner City"
      when 1.0..2.0
        "City Limits"
      when 2.0..5.0
        "Outer Playa"
      when 5.0..15.0
        "Deep Playa"
      when 15.0..50.0
        "Way Out There"
      else
        "RENO?!?!"
      end
    end

    # Detect nearby landmarks and return proximity info
    def detect_nearby_landmarks(lat, lng)
      landmarks = burning_man_landmarks
      nearby = []

      landmarks.each do |landmark|
        distance = haversine_distance(lat, lng, landmark[:lat], landmark[:lng])
        
        if distance <= landmark[:radius]
          nearby << {
            name: landmark[:name],
            type: landmark[:type],
            distance: distance,
            context: landmark[:context] || "Near #{landmark[:name]}"
          }
        end
      end

      nearby.sort_by { |l| l[:distance] }
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

    def fallback_location
      {
        lat: coordinates[:lat],
        lng: coordinates[:lng], 
        timestamp: Time.now,
        accuracy: nil,
        battery: nil,
        address: "Black Rock City",
        context: "Default Location"
      }
    end

    # Calculate bearing between two points
    def calculate_bearing(lat1, lng1, lat2, lng2)
      lat1_rad = lat1 * Math::PI / 180
      lat2_rad = lat2 * Math::PI / 180
      lng_diff = (lng2 - lng1) * Math::PI / 180

      y = Math.sin(lng_diff) * Math.cos(lat2_rad)
      x = Math.cos(lat1_rad) * Math.sin(lat2_rad) - 
          Math.sin(lat1_rad) * Math.cos(lat2_rad) * Math.cos(lng_diff)

      bearing = Math.atan2(y, x) * 180 / Math::PI
      (bearing + 360) % 360 # Normalize to 0-360
    end

    # Convert bearing to Burning Man time-based street
    def bearing_to_time_street(bearing)
      # BRC streets: 2:00 at 30°, 3:00 at 60°, etc.
      # Adjust for BRC orientation (2:00 is not due north)
      adjusted_bearing = (bearing + 60) % 360 # Offset for BRC orientation
      hour = ((adjusted_bearing / 30.0).round % 12)
      hour = 12 if hour == 0
      
      if (2..10).include?(hour)
        "#{hour}:00"
      else
        nil # Outside main city radials
      end
    end

    # Convert distance to lettered/named concentric street
    def distance_to_concentric_street(distance_miles)
      # BRC 2025 street names (innermost to outermost)
      streets = %w[Esplanade Atwood Bradbury Cherryh Dick Ellison Farmer Gibson Herbert Ishiguro Jemisin Kilgore]
      
      # Approximate distances (in miles from center)
      street_distances = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2]
      
      street_distances.each_with_index do |street_distance, index|
        if distance_miles <= street_distance
          return streets[index]
        end
      end
      
      "Beyond Kilgore" # Past the city limits
    end

    # Burning Man landmarks with GPS coordinates and proximity radii
    def burning_man_landmarks
      [
        {
          name: "Center Camp",
          lat: 40.786958,
          lng: -119.202994,
          radius: 300, # meters
          type: "gathering",
          context: "Center Camp - Heart of the City"
        },
        {
          name: "The Temple",
          lat: 40.7800,
          lng: -119.2030,
          radius: 200,
          type: "sacred",
          context: "Approaching the Temple 🏛️"
        },
        {
          name: "The Man",
          lat: 40.7850,
          lng: -119.2030,
          radius: 150,
          type: "center",
          context: "Near The Man 🔥"
        },
        {
          name: "Airport",
          lat: 40.6622,
          lng: -119.4341,
          radius: 500,
          type: "transport",
          context: "Black Rock City Airport ✈️"
        },
        {
          name: "Arctica (3:00 & G)",
          lat: 40.7865,
          lng: -119.2045,
          radius: 100,
          type: "service",
          context: "Near Arctica Ice Sales ❄️"
        },
        {
          name: "Arctica (6:15 & B)",
          lat: 40.7860,
          lng: -119.2025,
          radius: 100,
          type: "service",
          context: "Near Arctica Ice Sales ❄️"
        },
        {
          name: "Arctica (9:00 & G)",
          lat: 40.7855,
          lng: -119.2015,
          radius: 100,
          type: "service",
          context: "Near Arctica Ice Sales ❄️"
        },
        {
          name: "Emergency Services (3:00 & C)",
          lat: 40.7870,
          lng: -119.2040,
          radius: 150,
          type: "medical",
          context: "Near Emergency Medical 🚑"
        },
        {
          name: "Emergency Services (9:00 & C)",
          lat: 40.7850,
          lng: -119.2020,
          radius: 150,
          type: "medical",
          context: "Near Emergency Medical 🚑"
        }
      ]
    end

    # Detect nearby porto clusters
    def detect_nearby_portos(lat, lng)
      # This would load actual porto locations from the GeoJSON
      # For now, approximate based on known concentrations
      porto_clusters = [
        { name: "Esplanade Portos", lat: 40.7865, lng: -119.2030, radius: 50 },
        { name: "Deep Playa Portos", lat: 40.7800, lng: -119.2000, radius: 75 }
      ]

      nearby_portos = []
      porto_clusters.each do |cluster|
        distance = haversine_distance(lat, lng, cluster[:lat], cluster[:lng])
        if distance <= cluster[:radius]
          nearby_portos << {
            name: cluster[:name],
            distance: distance,
            type: "portos"
          }
        end
      end

      nearby_portos
    end

    # Determine map visual mode based on proximity
    def determine_map_mode(nearby_landmarks)
      return "normal" if nearby_landmarks.empty?

      primary_landmark = nearby_landmarks.first
      case primary_landmark[:type]
      when "sacred"
        "temple" # Desaturated, reverent colors
      when "center"
        "man" # Bright, energetic colors
      when "medical"
        "emergency" # Red highlights, clear navigation
      when "service"
        "service" # Blue highlights for utilities
      else
        "landmark" # Enhanced visibility
      end
    end

    # Determine visual effects for map display
    def determine_visual_effects(nearby_landmarks)
      effects = []
      
      nearby_landmarks.each do |landmark|
        case landmark[:type]
        when "sacred"
          effects << {
            type: "aura",
            color: "white",
            intensity: "soft",
            description: "Sacred space - respectful proximity"
          }
        when "center"
          effects << {
            type: "pulse",
            color: "orange",
            intensity: "strong",
            description: "Center of the burn - high energy"
          }
        when "medical"
          effects << {
            type: "beacon",
            color: "red",
            intensity: "steady",
            description: "Emergency services nearby"
          }
        when "service"
          effects << {
            type: "glow",
            color: "blue",
            intensity: "medium",
            description: "Services available"
          }
        end
      end

      effects
    end
  end
end