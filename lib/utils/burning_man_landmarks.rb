# frozen_string_literal: true

module Utils
  module BurningManLandmarks
    def self.load_landmarks
      landmarks_file = File.expand_path('../../data/gis/burning_man_landmarks.json', __dir__)

      unless File.exist?(landmarks_file)
        # Return basic landmarks if official data not available
        return default_landmarks
      end

      begin
        data = JSON.parse(File.read(landmarks_file))
        landmarks = data['landmarks'].map do |landmark|
          {
            name: landmark['name'],
            lat: landmark['lat'],
            lng: landmark['lng'],
            radius: landmark['radius'] || 30,
            type: landmark['type'] || 'poi',
            context: landmark['context'] || "Near #{landmark['name']}"
          }
        end

        # Filter to only include the most important landmarks for GPS proximity detection
        landmarks.select do |landmark|
          important_types = %w[center sacred gathering medical transport service]
          important_types.include?(landmark[:type])
        end
      rescue StandardError => e
        puts "Warning: Could not load official landmarks (#{e.message}), using defaults"
        default_landmarks
      end
    end

    def self.all_landmarks
      landmarks_file = File.expand_path('../../data/gis/burning_man_landmarks.json', __dir__)

      return [] unless File.exist?(landmarks_file)

      begin
        data = JSON.parse(File.read(landmarks_file))
        data['landmarks'].map do |landmark|
          {
            name: landmark['name'],
            lat: landmark['lat'],
            lng: landmark['lng'],
            radius: landmark['radius'] || 30,
            type: landmark['type'] || 'poi',
            context: landmark['context'] || "Near #{landmark['name']}",
            icon: landmark['icon'] || '📍'
          }
        end
      rescue StandardError
        []
      end
    end

    def self.default_landmarks
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
