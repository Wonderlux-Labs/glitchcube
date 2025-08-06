# frozen_string_literal: true

module Utils
  module GeoConstants
    # Distance conversion constants
    METERS_TO_MILES = 1609.34
    MILES_TO_METERS = 1 / METERS_TO_MILES
    KM_TO_MILES = 0.621371
    MILES_TO_KM = 1 / KM_TO_MILES
    
    # Approximate degrees per mile at BRC latitude (40.7°N)
    DEGREES_PER_MILE_LAT = 1.0 / 69.0  # Roughly constant
    DEGREES_PER_MILE_LNG = 1.0 / 54.6  # Varies with latitude
    
    # Burning Man specific coordinates
    BRC_CENTER_CAMP = {
      lat: 40.786958,
      lng: -119.202994,
      name: 'Center Camp',
      address: '2:00 & Atwood'
    }.freeze
    
    # BRC 2025 street names (innermost to outermost)
    BRC_STREETS = %w[
      Esplanade 
      Atwood 
      Bradbury 
      Cherryh 
      Dick 
      Ellison 
      Farmer 
      Gibson 
      Herbert 
      Ishiguro 
      Jemisin 
      Kilgore
    ].freeze
    
    # Approximate street distances from center (in miles)
    STREET_DISTANCES = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, 1.1, 1.2].freeze
    
    # Time-based radial streets (clock positions)
    TIME_STREETS = (2..10).map { |hour| "#{hour}:00" }.freeze
    
    # BRC coordinate system constants
    BRC_ORIENTATION_OFFSET = 30 # degrees adjustment for BRC street layout
    TIME_STREET_INTERVAL = 30  # degrees between time streets
    
    # Cache TTL values
    GPS_CACHE_TTL = 60          # 1 minute for GPS data
    LANDMARKS_CACHE_TTL = 300   # 5 minutes for landmark data
    ADDRESSES_CACHE_TTL = 3600  # 1 hour for address calculations
    
    # Burning Man proximity distances (much smaller scale!)
    PROXIMITY_DISTANCES = {
      landmarks: 25.0 / 5280.0,    # 25 feet in miles (~0.005 miles)
      toilets: 50.0 / 5280.0,      # 50 feet in miles (~0.009 miles) 
      art: 100.0 / 5280.0,         # 100 feet in miles (~0.019 miles)
      camps: 150.0 / 5280.0,       # 150 feet in miles (~0.028 miles)
      services: 200.0 / 5280.0     # 200 feet in miles (~0.038 miles)
    }.freeze
    
    # Distance ranges for location context (these can stay larger)
    DISTANCE_RANGES = {
      center_camp: 0.02,      # ~30 meters
      inner_city: 1.0,        # ~1.6km  
      outer_playa: 3.0,       # ~4.8km
      deep_playa: 10.0,       # ~16km
      way_out_there: 50.0     # ~80km
    }.freeze
  end
end