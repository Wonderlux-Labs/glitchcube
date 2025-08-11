# frozen_string_literal: true

# Service for efficiently querying spatial context around the cube using PostGIS
module Services
  class CubeProximityService
    CACHE_TTL = 5 # seconds

    # Get comprehensive nearby context for the cube's current location
    # Returns nearest landmarks, current boundary, and fence status
    def self.nearby_context(lat, lng)
      cache_key = "cube_proximity:#{lat.round(5)}:#{lng.round(5)}"

      Services::GpsCacheService.cache_fetch(cache_key, expires_in: CACHE_TTL) do
        {
          nearest_landmarks: fetch_nearest_landmarks(lng, lat),
          current_boundary: fetch_current_boundary(lng, lat),
          fence_status: Boundary.within_fence?(lat, lng),
          nearest_streets: fetch_nearest_streets(lng, lat),
          location_description: build_location_description(lng, lat)
        }
      end
    end

    # Get a human-readable description of the current location
    def self.location_description(lat, lng)
      context = nearby_context(lat, lng)
      build_location_description_from_context(context)
    end

    # Check if cube is near any significant landmarks
    def self.near_significant_landmark?(lat, lng, threshold_meters = 50)
      landmarks = Landmark.nearest(lng: lng, lat: lat, limit: 1)
      return false if landmarks.empty?

      landmark = landmarks.first
      return false unless landmark.respond_to?(:distance_meters)

      landmark.distance_meters <= threshold_meters
    end

    # Get proximity alerts for interesting nearby features
    def self.proximity_alerts(lat, lng)
      alerts = []

      # Check for nearby art installations
      art = Landmark.by_type('art').nearest(lng: lng, lat: lat, limit: 1).first
      if art.respond_to?(:distance_meters) && art.distance_meters < 100
        alerts << {
          type: 'art',
          name: art.name,
          distance: art.distance_meters.round,
          message: "Art installation '#{art.name}' is #{art.distance_meters.round}m away!"
        }
      end

      # Check for emergency services
      medical = Landmark.by_type('medical').nearest(lng: lng, lat: lat, limit: 1).first
      if medical.respond_to?(:distance_meters) && medical.distance_meters < 200
        alerts << {
          type: 'medical',
          name: medical.name,
          distance: medical.distance_meters.round,
          message: "Medical station nearby at #{medical.distance_meters.round}m"
        }
      end

      # Check if approaching fence boundary
      unless Boundary.within_fence?(lat, lng)
        alerts << {
          type: 'boundary',
          name: 'Trash Fence',
          message: 'Warning: Outside the trash fence boundary!'
        }
      end

      alerts
    end

    private

    def self.fetch_nearest_landmarks(lng, lat, limit = 3)
      landmarks = Landmark.nearest(lng: lng, lat: lat, limit: limit)
      landmarks.map do |landmark|
        {
          name: landmark.name,
          type: landmark.landmark_type,
          distance_meters: landmark.respond_to?(:distance_meters) ? landmark.distance_meters.round : nil,
          description: landmark.description
        }
      end
    end

    def self.fetch_current_boundary(lng, lat)
      boundary = Boundary.containing_point(lng, lat).first
      return nil unless boundary

      {
        name: boundary.name,
        type: boundary.boundary_type,
        description: boundary.description
      }
    end

    def self.fetch_nearest_streets(lng, lat, limit = 2)
      streets = Street.nearest(lng: lng, lat: lat, limit: limit)
      streets.map do |street|
        {
          name: street.name,
          type: street.street_type,
          distance_meters: street.respond_to?(:distance_meters) ? street.distance_meters.round : nil
        }
      end
    end

    def self.build_location_description(lng, lat)
      context = {
        nearest_landmarks: fetch_nearest_landmarks(lng, lat),
        current_boundary: fetch_current_boundary(lng, lat),
        nearest_streets: fetch_nearest_streets(lng, lat)
      }
      build_location_description_from_context(context)
    end

    def self.build_location_description_from_context(context)
      parts = []

      # Add boundary info if available
      if context[:current_boundary]
        parts << "in #{context[:current_boundary][:name]}"
      end

      # Add nearest street info
      if context[:nearest_streets] && !context[:nearest_streets].empty?
        street = context[:nearest_streets].first
        parts << if street[:distance_meters] && street[:distance_meters] < 50
                   "on #{street[:name]}"
                 else
                   "near #{street[:name]}"
                 end
      end

      # Add nearest landmark
      if context[:nearest_landmarks] && !context[:nearest_landmarks].empty?
        landmark = context[:nearest_landmarks].first
        if landmark[:distance_meters]
          parts << "#{landmark[:distance_meters]}m from #{landmark[:name]}"
        end
      end

      parts.empty? ? 'Unknown location' : parts.join(', ')
    end
  end
end
