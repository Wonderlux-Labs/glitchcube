# frozen_string_literal: true

require_relative '../../config/constants'

module Utils
  module LocationHelper
    # Get current coordinates
    def coordinates
      GlitchCube::Constants::COORDINATES
    end

    # Get location info
    def location
      GlitchCube::Constants::LOCATION
    end

    # Format coordinates for API calls
    def coordinates_string
      GlitchCube::Constants::COORDINATES[:lat_lng_string]
    end

    # Get weather API endpoints
    def weather_endpoints
      coords = coordinates_string
      {
        nws: "https://api.weather.gov/points/#{coords}",
        openweather: "https://api.openweathermap.org/data/2.5/weather?lat=#{coordinates[:lat]}&lon=#{coordinates[:lng]}",
        weather_gov_forecast: 'https://api.weather.gov/gridpoints/REV/41,106/forecast' # Black Rock Desert grid
      }
    end

    # Calculate distance from installation (in miles)
    def distance_from(lat, lng)
      haversine_distance(coordinates[:lat], coordinates[:lng], lat, lng)
    end

    # Calculate distance between two points using geocoder gem (in miles)
    def haversine_distance(lat1, lng1, lat2, lng2)
      require 'geocoder'
      require 'geocoder/calculations'
      # Ensure geocoder is configured for calculations
      Geocoder.configure(units: :mi) unless Geocoder.config.units
      Geocoder::Calculations.distance_between([lat1, lng1], [lat2, lng2], units: :mi).round(6)
    end

    # Calculate bearing between two points using geocoder gem (returns 0-360 degrees)
    def calculate_bearing(lat1, lng1, lat2, lng2)
      require 'geocoder'
      require 'geocoder/calculations'
      # Ensure geocoder is configured for calculations
      Geocoder.configure(units: :mi) unless Geocoder.config.units
      Geocoder::Calculations.bearing_between([lat1, lng1], [lat2, lng2]).round(6)
    end

    # Get compass direction from bearing (N, NE, E, SE, S, SW, W, NW)
    def bearing_to_compass(bearing)
      directions = %w[N NE E SE S SW W NW]
      directions[(bearing / 45.0).round % 8]
    end

    # Get timezone
    def timezone
      location[:timezone]
    end

    # Get current time in installation timezone
    def current_time
      require 'tzinfo'
      tz = TZInfo::Timezone.get(timezone)
      tz.now
    end

    # Burning Man trash fence coordinates (perimeter polygon)
    def trash_fence_coordinates
      [
        [-119.23273810046265, 40.783393446219854],
        [-119.20773209353101, 40.764368446672798], 
        [-119.17619408998932, 40.776562450337401],
        [-119.18168009473258, 40.80310545215228],
        [-119.21663410121434, 40.80735944960616],
        [-119.23273810046265, 40.783393446219854] # Close the polygon
      ]
    end

    # Check if coordinates are within the Burning Man perimeter (trash fence)
    def within_trash_fence?(lat, lng)
      point_in_polygon?(lat, lng, trash_fence_coordinates)
    end

    # Point-in-polygon algorithm (ray casting)
    def point_in_polygon?(lat, lng, polygon_coords)
      inside = false
      j = polygon_coords.length - 1
      
      (0...polygon_coords.length).each do |i|
        coord_i = polygon_coords[i]
        coord_j = polygon_coords[j]
        
        if ((coord_i[1] > lng) != (coord_j[1] > lng)) &&
           (lat < (coord_j[0] - coord_i[0]) * (lng - coord_i[1]) / (coord_j[1] - coord_i[1]) + coord_i[0])
          inside = !inside
        end
        j = i
      end
      
      inside
    end
  end
end
