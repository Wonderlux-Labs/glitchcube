# frozen_string_literal: true

module GlitchCube
  module Constants
    # Location: Black Rock City (Burning Man location)
    LOCATION = {
      city: 'Black Rock City',
      state: 'Nevada',
      country: 'USA',
      latitude: 40.7864,
      longitude: -119.2065,
      timezone: 'America/Los_Angeles', # Pacific Time
      timezone_name: 'Pacific Time'
    }.freeze

    # Geographic coordinates for weather APIs and location-based services
    COORDINATES = {
      lat: 40.7864,
      lng: -119.2065,
      lat_lng: [40.7864, -119.2065],
      lat_lng_string: '40.7864,-119.2065'
    }.freeze

    # Installation location details
    INSTALLATION = {
      name: 'Glitch Cube',
      type: 'Interactive Art Installation',
      venue: 'Various Locations',
      default_location: 'Nevada Desert'
    }.freeze

    # Weather API configuration placeholders
    WEATHER = {
      update_interval: 3600, # 1 hour in seconds
      units: 'imperial', # Fahrenheit for US
      default_conditions: {
        temperature: 72,
        humidity: 30,
        description: 'Clear skies'
      }
    }.freeze
  end
end
