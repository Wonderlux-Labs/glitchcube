# frozen_string_literal: true

module Services
  class LocationContextService
    THE_MAN_COORDS = { lat: 40.78696345, lng: -119.2030071 }.freeze

    class << self
      # Get comprehensive location context
      def full_context(lat, lng)
        {
          zone: determine_zone(lat, lng),
          address: get_address(lat, lng),
          intersection: Street.nearest_intersection(lat, lng),
          landmarks: nearby_landmarks(lat, lng),
          within_fence: Boundary.cube_within_fence?(lat, lng),
          city_block: get_city_block(lat, lng),
          distance_from_man: distance_from_man(lat, lng)
        }
      end

      # Determine which zone we're in
      def determine_zone(lat, lng)
        # Check if we're outside the fence
        unless Boundary.cube_within_fence?(lat, lng)
          return 'Outside Event'
        end

        # Check if we're in a city block
        if Boundary.in_city?(lat, lng)
          return 'In The City'
        end

        # Get distance from The Man to determine playa zone
        distance = Utils::BrcCoordinateService.distance_between_points(
          THE_MAN_COORDS[:lat], THE_MAN_COORDS[:lng], lat, lng
        )

        # Based on BRC layout:
        # - Inner Playa: Between Esplanade and The Man (< 0.47 miles)
        # - Mid Playa: Between city and deep playa (0.47 - 1.0 miles)
        # - Deep Playa: Far from city (> 1.0 miles)

        if distance < 0.47  # Inside Esplanade
          'Inner Playa'
        elsif distance < 1.0
          'Mid Playa'
        else
          'Deep Playa'
        end
      end

      # Get BRC address or playa description
      def get_address(lat, lng)
        # First try to get street intersection
        intersection = Street.nearest_intersection(lat, lng)

        # If we have both streets and they're close, use that
        if intersection[:radial] && intersection[:arc] &&
           intersection[:radial_distance] < 100 && intersection[:arc_distance] < 100
          return "#{intersection[:radial]} & #{intersection[:arc]}"
        end

        # Otherwise fall back to zone description
        zone = determine_zone(lat, lng)
        case zone
        when 'In The City'
          # Try to get nearest streets even if not at intersection
          if intersection[:radial] && intersection[:arc]
            "Near #{intersection[:radial]} & #{intersection[:arc]}"
          else
            'In The City'
          end
        when 'Inner Playa'
          # Might be near an art piece or between streets
          bearing = Utils::BrcCoordinateService.bearing_between_points(
            THE_MAN_COORDS[:lat], THE_MAN_COORDS[:lng], lat, lng
          )
          time = bearing_to_clock(bearing)
          "Inner Playa near #{time}"
        when 'Deep Playa'
          # Far out, use bearing from Man
          bearing = Utils::BrcCoordinateService.bearing_between_points(
            THE_MAN_COORDS[:lat], THE_MAN_COORDS[:lng], lat, lng
          )
          time = bearing_to_clock(bearing)
          "Deep Playa towards #{time}"
        else
          zone
        end
      end

      # Get nearby landmarks with context
      def nearby_landmarks(lat, lng, limit = 3)
        landmarks = Landmark.nearest(lat: lat, lng: lng, limit: limit)
        landmarks.map do |lm|
          {
            name: lm.name,
            type: lm.landmark_type,
            distance_meters: lm.distance_meters
          }
        end
      end

      # Get city block info if in one
      def get_city_block(lat, lng)
        block = Boundary.containing_city_block(lat, lng)
        return nil unless block

        {
          name: block.name,
          id: block.properties['fid']
        }
      end

      # Calculate distance from The Man
      def distance_from_man(lat, lng)
        distance_miles = Utils::BrcCoordinateService.distance_between_points(
          THE_MAN_COORDS[:lat], THE_MAN_COORDS[:lng], lat, lng
        )

        # Convert to feet if close
        if distance_miles < 0.1
          "#{(distance_miles * 5280).round} feet"
        else
          "#{distance_miles.round(2)} miles"
        end
      end

      private

      # Convert bearing to clock position
      def bearing_to_clock(bearing)
        # Normalize bearing to 0-360
        bearing %= 360

        # BRC uses clock positions where 3:00 is due north (0°)
        # Adjust bearing so 0° = 3:00
        adjusted = (bearing + 90) % 360

        # Convert to clock position
        hour = (adjusted / 30).round
        hour = 12 if hour.zero?

        # Get minutes for more precision
        minutes = ((adjusted % 30) * 2).round

        if minutes.zero?
          "#{hour}:00"
        elsif minutes == 30
          "#{hour}:30"
        elsif minutes < 30
          "#{hour}:#{minutes.to_s.rjust(2, '0')}"
        else
          next_hour = hour == 12 ? 1 : hour + 1
          "#{hour}:#{60 - minutes}"
        end
      end
    end
  end
end
