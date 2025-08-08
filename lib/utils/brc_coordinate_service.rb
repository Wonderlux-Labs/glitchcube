# frozen_string_literal: true

require 'geocoder'

module Utils
  # Single source of truth for all BRC coordinate calculations
  # Uses real street distances from official BRC 2025 GIS data
  class BrcCoordinateService
    # Configure geocoder once
    Geocoder.configure(units: :mi) unless Geocoder.config.units

    # GOLDEN_SPIKE_COORDS - canonical center for BRC and all map logic
    # Use this everywhere as the single source of truth for the city center.
    GOLDEN_SPIKE_COORDS = { lat: 40.78696345, lng: -119.2030071 }.freeze
    THE_MAN_COORDS = GOLDEN_SPIKE_COORDS

    # REAL street distances from The Man (calculated from BRC GIS data)
    STREET_DISTANCES = {
      'Esplanade' => 0.472,
      'Atwood' => 0.554,
      'Bradbury' => 0.607,
      'Cherryh' => 0.66,
      'Dick' => 0.713,
      'Ellison' => 0.767,
      'Farmer' => 0.861,
      'Gibson' => 0.914,
      'Herbert' => 0.967,
      'Ishiguro' => 1.02,
      'Jemisin' => 1.054,
      'Kilgore' => 1.09
    }.freeze

    # Street order for distance-based lookup
    STREETS_BY_DISTANCE = STREET_DISTANCES.sort_by { |_name, dist| dist }.map(&:first).freeze

    class << self
      # Convert GPS coordinates to BRC address format
      def brc_address_from_coordinates(lat, lng)
        # Calculate distance from GOLDEN_SPIKE_COORDS
        distance = distance_between_points(GOLDEN_SPIKE_COORDS[:lat], GOLDEN_SPIKE_COORDS[:lng], lat, lng)

        # Get radial street (time-based) using GOLDEN_SPIKE_COORDS as center
        bearing = bearing_between_points(GOLDEN_SPIKE_COORDS[:lat], GOLDEN_SPIKE_COORDS[:lng], lat, lng)
        radial_street = bearing_to_time_street(bearing)

        # Check if we're in deep playa (beyond the city)
        if distance > 1.2 # Beyond Kilgore distance
          return 'Deep Playa'
        elsif distance > 1.09 # Beyond last street but not deep playa
          return 'Outer Playa'
        end

        # Get concentric street (lettered/named) using REAL distances
        concentric_street = distance_to_concentric_street(distance)

        if radial_street && concentric_street
          "#{radial_street} & #{concentric_street}"
        else
          'Inner Playa'
        end
      end

      # Calculate distance between two GPS points (in miles)
      def distance_between_points(lat1, lng1, lat2, lng2)
        Geocoder::Calculations.distance_between([lat1, lng1], [lat2, lng2], units: :mi)
      end

      # Calculate bearing between two GPS points (0-360 degrees)
      def bearing_between_points(lat1, lng1, lat2, lng2)
        Geocoder::Calculations.bearing_between([lat1, lng1], [lat2, lng2])
      end

      # Get GOLDEN_SPIKE coordinates (canonical center)
      def golden_spike_coordinates
        GOLDEN_SPIKE_COORDS
      end


      private

      # Convert distance to BRC concentric street using REAL data
      def distance_to_concentric_street(distance_miles)
        # Define tolerance for being "at" a street (within ~100 feet)
        street_tolerance = 0.02 # miles (~100 feet)

        # Check if we're exactly at a street (within tolerance)
        STREET_DISTANCES.each do |street_name, street_distance|
          return street_name if (distance_miles - street_distance).abs <= street_tolerance
        end

        # Not at any street - find which area we're in
        if distance_miles > 1.2
          'Beyond Kilgore'
        elsif distance_miles < STREET_DISTANCES['Esplanade'] - street_tolerance
          'Inner Plaza' # Between The Man and Esplanade
        else
          # Between streets - find which two
          sorted_streets = STREET_DISTANCES.sort_by { |_, dist| dist }

          sorted_streets.each_cons(2) do |(inner_street, inner_dist), (outer_street, outer_dist)|
            return "#{inner_street}-#{outer_street} Area" if distance_miles > inner_dist + street_tolerance && distance_miles < outer_dist - street_tolerance
          end

          # Fallback to closest street if no area match
          STREET_DISTANCES.min_by { |_, dist| (distance_miles - dist).abs }.first

        end
      end

      # Convert bearing to BRC time-based street with 30-minute increments
      def bearing_to_time_street(bearing)
        # BRC ACTUAL layout: 6:00 = 180° (due south), streets 2:00-10:00
        # Total arc is 240° (from 2:00 to 10:00)
        # 6:00 = 180°, so 2:00 = 60°, 10:00 = 300°

        # Normalize bearing to 0-360 (no offset needed)
        normalized_bearing = bearing % 360

        # Convert to BRC time: 6:00 = 180°, each hour = 30°
        # Formula: time = 6 + (normalized_bearing - 180) / 30
        hour_decimal = 6.0 + ((normalized_bearing - 180.0) / 30.0)

        # Handle the time calculation
        hour = hour_decimal.floor
        minutes_decimal = (hour_decimal - hour) * 60

        # Round to nearest 30 minutes
        if minutes_decimal < 15
          minutes = 0
        elsif minutes_decimal < 45
          minutes = 30
        else
          hour += 1
          minutes = 0
        end

        # Wrap around at 12
        hour %= 12
        hour = 12 if hour.zero?

        # Format time string
        time_str = if minutes.zero?
                     "#{hour}:00"
                   else
                     "#{hour}:30"
                   end

        # Only return valid BRC times (2:00 to 10:00)
        if hour.between?(2, 10)
          time_str
        elsif [1, 11].include?(hour)
          # Outside main street grid
          hour <= 6 ? '2:00' : '10:00'
        end
        # Returns nil for deep playa (hours outside 1-11)
      end
    end
  end
end
