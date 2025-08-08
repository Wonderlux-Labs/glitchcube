# frozen_string_literal: true

# Load required classes
require_relative 'initializers/config' unless defined?(GlitchCube::Config)

module GlitchCube
  # Version
  VERSION = '1.0.0'

  # Runtime attributes
  class << self
    attr_accessor :start_time

    # Configuration
    def config
      @config ||= Config.instance
    end

    # Logger
    def logger
      @logger ||= Services::LoggerService
    end

    # Root directory
    def root
      @root ||= File.expand_path('..', __dir__)
    end

    # Persistence availability check
    def persistence_enabled?
      config.persistence_enabled?
    end

    # Redis connection
    def redis_connection
      return @redis if defined?(@redis) && @redis

      redis_url = config.redis_url
      if redis_url && !redis_url.empty?
        require 'redis'
        @redis = Redis.new(url: redis_url)
      end
    rescue StandardError => e
      logger.warn('⚠️ Failed to connect to Redis', error: e.message)
      nil
    end
  end

  module Constants
    # Location: Black Rock City (Burning Man location) - Golden Spike coordinates
    LOCATION = {
      city: 'Black Rock City',
      state: 'Nevada',
      country: 'USA',
      latitude: 40.786958, # Golden Spike (Center Camp) latitude
      longitude: -119.202994, # Golden Spike (Center Camp) longitude
      timezone: 'America/Los_Angeles', # Pacific Time
      timezone_name: 'Pacific Time'
    }.freeze

    # Geographic coordinates for weather APIs and location-based services
    COORDINATES = {
      lat: 40.786958, # Golden Spike (Center Camp) latitude
      lng: -119.202994, # Golden Spike (Center Camp) longitude
      lat_lng: [40.786958, -119.202994],
      lat_lng_string: '40.786958,-119.202994'
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
