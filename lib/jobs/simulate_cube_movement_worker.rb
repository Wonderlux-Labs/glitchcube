# frozen_string_literal: true

require 'sidekiq'
require 'json'
require 'fileutils'
require_relative '../cube/settings'
require_relative '../utils/location_helper'
require_relative '../services/gps_tracking_service'
require_relative '../home_assistant_client'

module Jobs
  class SimulateCubeMovementWorker
    include Sidekiq::Worker
    include Utils::LocationHelper

    # File paths for simulation data
    CONFIG_FILE = File.expand_path('../../data/simulation/gps_simulation_config.json', __dir__)
    SIM_FILE = File.expand_path('../../data/simulation/current_coordinates.json', __dir__)
    HISTORY_FILE = File.expand_path('../../data/simulation/route_history.json', __dir__)
    DEST_FILE = File.expand_path('../../data/simulation/current_destination.json', __dir__)
    STEP_FILE = File.expand_path('../../data/simulation/movement_step.txt', __dir__)

    def perform
      return unless Cube::Settings.simulate_cube_movement?

      load_configuration
      @start_time = Time.now
      @current_location = load_current_location
      @destination = load_or_pick_destination
      @route_history = load_history

      logger.info '🎲 Starting cube movement simulation'
      logger.info "   Current: #{format_location(@current_location)}"
      logger.info "   Destination: #{@destination[:name]}"

      while should_continue?
        move_toward_destination
        save_current_state
        log_movement

        # Check if we've arrived
        if arrived_at_destination?
          logger.info "✅ Arrived at #{@destination[:name]}!"
          pick_new_destination
        end

        sleep @config['movement']['update_interval']
      end

      logger.info '🛑 Stopping cube movement simulation (time limit reached)'
    end

    private

    def load_configuration
      @config = if File.exist?(CONFIG_FILE)
                  JSON.parse(File.read(CONFIG_FILE))
                else
                  # Default configuration if file doesn't exist
                  {
                    'destinations' => default_destinations,
                    'movement' => {
                      'speed' => 0.0001,
                      'arrival_threshold' => 0.0005,
                      'update_interval' => 10,
                      'max_duration' => 1800,
                      'wander_factor' => 0.2
                    },
                    'start_location' => {
                      'lat' => 40.7840,
                      'lng' => -119.2060,
                      'name' => '6:00 & Kilgore'
                    }
                  }
                end
    end

    def default_destinations
      [
        { 'name' => 'Center Camp', 'lat' => 40.786958, 'lng' => -119.202994, 'type' => 'gathering' },
        { 'name' => 'The Man', 'lat' => 40.786963, 'lng' => -119.203007, 'type' => 'center' },
        { 'name' => 'The Temple', 'lat' => 40.791815, 'lng' => -119.196622, 'type' => 'sacred' }
      ]
    end

    def should_continue?
      (Time.now - @start_time) < @config['movement']['max_duration'] &&
        Cube::Settings.simulate_cube_movement?
    end

    def load_current_location
      if File.exist?(SIM_FILE)
        begin
          coords = JSON.parse(File.read(SIM_FILE))
          return { lat: coords['lat'], lng: coords['lng'] }
        rescue StandardError
          # Fall through to default
        end
      end

      # No existing simulation - pick a random starting destination
      random_start = @config['destinations'].sample
      logger.info "🎯 Starting simulation at random location: #{random_start['name']}"
      
      {
        lat: random_start['lat'],
        lng: random_start['lng']
      }
    end

    def load_or_pick_destination
      if File.exist?(DEST_FILE)
        begin
          dest = JSON.parse(File.read(DEST_FILE))
          found = @config['destinations'].find { |d| d['name'] == dest['name'] }
          return found.transform_keys(&:to_sym) if found
        rescue StandardError
          # Fall through
        end
      end
      pick_random_destination
    end

    def pick_random_destination
      # Don't pick current location as destination
      available = @config['destinations'].reject do |dest|
        distance = haversine_distance(
          @current_location[:lat], @current_location[:lng],
          dest['lat'], dest['lng']
        )
        distance < 0.1 # Less than ~100m away
      end

      destination = available.sample.transform_keys(&:to_sym)
      save_destination(destination)
      destination
    end

    def pick_new_destination
      @destination = pick_random_destination
      logger.info "🎯 New destination: #{@destination[:name]}"
    end

    def move_toward_destination
      # Calculate direction to destination
      lat_diff = @destination[:lat] - @current_location[:lat]
      lng_diff = @destination[:lng] - @current_location[:lng]

      # Normalize the movement vector
      distance = Math.sqrt((lat_diff**2) + (lng_diff**2))

      return unless distance.positive?

      # Add some randomness to movement (wandering)
      wander = @config['movement']['wander_factor']
      speed = @config['movement']['speed']
      lat_move = ((lat_diff / distance) * speed) + (rand(-wander..wander) * speed)
      lng_move = ((lng_diff / distance) * speed) + (rand(-wander..wander) * speed)

      @current_location[:lat] += lat_move
      @current_location[:lng] += lng_move

      # Add to history
      @route_history << {
        lat: @current_location[:lat],
        lng: @current_location[:lng],
        timestamp: Time.now.utc.iso8601,
        destination: @destination[:name]
      }

      # Keep history to last 100 points
      @route_history = @route_history.last(100)
    end

    def arrived_at_destination?
      threshold = @config['movement']['arrival_threshold']
      lat_diff = (@destination[:lat] - @current_location[:lat]).abs
      lng_diff = (@destination[:lng] - @current_location[:lng]).abs

      lat_diff < threshold && lng_diff < threshold
    end

    def save_current_state
      # Calculate BRC address
      gps_service = Services::GpsTrackingService.new
      address = gps_service.brc_address_from_coordinates(
        @current_location[:lat],
        @current_location[:lng]
      )
      context = gps_service.location_context(
        @current_location[:lat],
        @current_location[:lng]
      )

      # Save current coordinates
      coords = {
        lat: @current_location[:lat].round(6),
        lng: @current_location[:lng].round(6),
        timestamp: Time.now.utc.iso8601,
        address: address,
        context: context,
        source: 'simulation'
      }

      ensure_directory(File.dirname(SIM_FILE))
      File.write(SIM_FILE, JSON.pretty_generate(coords))

      # Save history
      save_history
    end

    def save_history
      ensure_directory(File.dirname(HISTORY_FILE))
      File.write(HISTORY_FILE, JSON.pretty_generate(@route_history))
    end

    def load_history
      if File.exist?(HISTORY_FILE)
        begin
          JSON.parse(File.read(HISTORY_FILE))
        rescue StandardError
          []
        end
      else
        []
      end
    end

    def save_destination(destination)
      ensure_directory(File.dirname(DEST_FILE))
      File.write(DEST_FILE, JSON.pretty_generate(destination))
    end

    def ensure_directory(dir)
      FileUtils.mkdir_p(dir) unless File.directory?(dir)
    end

    def calculate_distance_to_destination
      haversine_distance(
        @current_location[:lat], @current_location[:lng],
        @destination[:lat], @destination[:lng]
      )
    end

    def format_location(loc)
      "#{loc[:lat].round(6)}, #{loc[:lng].round(6)}"
    end

    def log_movement
      distance = calculate_distance_to_destination
      meters = (distance * 1609.34).round
      logger.info "📍 Cube at: #{format_location(@current_location)} | " \
                  "Heading to: #{@destination[:name]} (#{meters}m away)"
    end

    # Calculate distance using Haversine formula
    def haversine_distance(lat1, lng1, lat2, lng2)
      r = 3959 # Earth's radius in miles

      lat1_rad = lat1 * Math::PI / 180
      lat2_rad = lat2 * Math::PI / 180
      lat_diff = (lat2 - lat1) * Math::PI / 180
      lng_diff = (lng2 - lng1) * Math::PI / 180

      a = (Math.sin(lat_diff / 2)**2) +
          (Math.cos(lat1_rad) * Math.cos(lat2_rad) *
          (Math.sin(lng_diff / 2)**2))

      c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
      r * c
    end
  end
end