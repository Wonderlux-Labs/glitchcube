# frozen_string_literal: true

module Utils
  module BurningManLandmarks
    def self.load_landmarks
      # Use ActiveRecord Landmark model instead of hardcoded data
      begin
        # Filter to only include the most important landmarks for GPS proximity detection
        important_types = %w[center sacred gathering medical transport service]
        
        landmarks = Landmark.active.where(landmark_type: important_types).map do |landmark|
          {
            name: landmark.name,
            lat: landmark.latitude,
            lng: landmark.longitude,
            radius: landmark.radius_meters,
            type: landmark.landmark_type,
            context: landmark.description || "Near #{landmark.name}"
          }
        end
        
        # Return default landmarks if database query returns empty
        return default_landmarks if landmarks.empty?
        
        landmarks
      rescue StandardError => e
        puts "Warning: Could not load landmarks from database (#{e.message}), using defaults"
        default_landmarks
      end
    end

    def self.all_landmarks
      # Use ActiveRecord Landmark model for all landmarks
      begin
        Landmark.active.map do |landmark|
          {
            name: landmark.name,
            lat: landmark.latitude,
            lng: landmark.longitude,
            radius: landmark.radius_meters,
            type: landmark.landmark_type,
            context: landmark.description || "Near #{landmark.name}",
            icon: landmark.icon || '📍'
          }
        end
      rescue StandardError => e
        puts "Warning: Could not load all landmarks from database (#{e.message})"
        []
      end
    end

    def self.default_landmarks
      # Minimal hardcoded fallbacks for when database is unavailable
      [
        {
          name: 'Center Camp',
          lat: 40.786958,
          lng: -119.202994,
          radius: 50,
          type: 'gathering',
          context: 'Center Camp - Heart of the City'
        },
        {
          name: 'The Temple',
          lat: 40.791815,
          lng: -119.196622,
          radius: 15,
          type: 'sacred',
          context: 'Approaching the Temple 🏛️'
        },
        {
          name: 'The Man',
          lat: 40.786963,
          lng: -119.203007,
          radius: 15,
          type: 'center',
          context: 'Near The Man 🔥'
        }
      ]
    end
  end
end
