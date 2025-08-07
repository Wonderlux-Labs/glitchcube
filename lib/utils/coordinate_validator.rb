# frozen_string_literal: true

module Utils
  # Validates GPS coordinates to ensure they're within valid ranges
  module CoordinateValidator
    VALID_LATITUDE_RANGE = (-90.0..90.0)
    VALID_LONGITUDE_RANGE = (-180.0..180.0)

    # Burning Man perimeter boundaries (approximate)
    BRC_BOUNDS = {
      north: 40.81,
      south: 40.76,
      east: -119.17,
      west: -119.24
    }.freeze

    class << self
      def valid_coordinates?(lat, lng)
        valid_latitude?(lat) && valid_longitude?(lng)
      end

      def valid_latitude?(lat)
        return false unless numeric?(lat)

        VALID_LATITUDE_RANGE.include?(lat.to_f)
      end

      def valid_longitude?(lng)
        return false unless numeric?(lng)

        VALID_LONGITUDE_RANGE.include?(lng.to_f)
      end

      def within_brc_bounds?(lat, lng)
        return false unless valid_coordinates?(lat, lng)

        lat_f = lat.to_f
        lng_f = lng.to_f

        lat_f.between?(BRC_BOUNDS[:south], BRC_BOUNDS[:north]) &&
          lng_f >= BRC_BOUNDS[:west] &&
          lng_f <= BRC_BOUNDS[:east]
      end

      def sanitize_coordinates(lat, lng)
        lat_f = lat.to_f.clamp(VALID_LATITUDE_RANGE.min, VALID_LATITUDE_RANGE.max)
        lng_f = lng.to_f.clamp(VALID_LONGITUDE_RANGE.min, VALID_LONGITUDE_RANGE.max)

        [lat_f, lng_f]
      end

      def validate_and_sanitize!(lat, lng)
        raise ArgumentError, "Invalid coordinates: lat=#{lat}, lng=#{lng}" unless valid_coordinates?(lat, lng)

        sanitize_coordinates(lat, lng)
      end

      private

      def numeric?(value)
        return false if value.nil?

        begin
          Float(value)
        rescue StandardError
          false
        end
      end
    end
  end
end
