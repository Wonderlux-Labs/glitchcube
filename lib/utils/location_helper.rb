# frozen_string_literal: true

require_relative '../../config/constants'

module Utils
  module LocationHelper
    module_function

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
      # Haversine formula for great-circle distance
      r = 3959 # Earth's radius in miles
      lat1 = coordinates[:lat] * Math::PI / 180
      lat2 = lat * Math::PI / 180
      dlat = (lat - coordinates[:lat]) * Math::PI / 180
      dlng = (lng - coordinates[:lng]) * Math::PI / 180

      a = (Math.sin(dlat / 2)**2) + (Math.cos(lat1) * Math.cos(lat2) * (Math.sin(dlng / 2)**2))
      c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))

      (r * c).round(2)
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
  end
end
