# frozen_string_literal: true

module Cube
  module Settings
    class << self
      # Feature Toggles
      def simulate_cube_movement?
        # Default: true in development, false in production
        # Can be overridden with SIMULATE_CUBE_MOVEMENT env var
        if ENV.key?('SIMULATE_CUBE_MOVEMENT')
          env_true?('SIMULATE_CUBE_MOVEMENT')
        else
          development?
        end
      end

      def mock_home_assistant?
        env_true?('MOCK_HOME_ASSISTANT')
      end

      def disable_circuit_breakers?
        env_true?('DISABLE_CIRCUIT_BREAKERS')
      end

      def mac_mini_deployment?
        env_true?('MAC_MINI_DEPLOYMENT')
      end

      # Environment
      def rack_env
        ENV.fetch('RACK_ENV', 'development')
      end

      def development?
        rack_env == 'development'
      end

      def test?
        rack_env == 'test'
      end

      def production?
        rack_env == 'production'
      end

      # Application Settings
      def app_root
        ENV['APP_ROOT'] || Dir.pwd
      end

      def session_secret
        ENV.fetch('SESSION_SECRET', nil)
      end

      # API Keys and Tokens
      def openrouter_api_key
        ENV.fetch('OPENROUTER_API_KEY', nil)
      end

      def openai_api_key
        ENV.fetch('OPENAI_API_KEY', nil)
      end

      def anthropic_api_key
        ENV.fetch('ANTHROPIC_API_KEY', nil)
      end

      def helicone_api_key
        ENV.fetch('HELICONE_API_KEY', nil)
      end

      def home_assistant_token
        ENV['HOME_ASSISTANT_TOKEN'] || ENV.fetch('HA_TOKEN', nil)
      end

      def github_webhook_secret
        ENV.fetch('GITHUB_WEBHOOK_SECRET', nil)
      end

      def beacon_token
        ENV.fetch('BEACON_TOKEN', nil)
      end

      def master_password
        ENV.fetch('MASTER_PASSWORD', nil)
      end

      # URLs and Endpoints
      def home_assistant_url
        ENV['HOME_ASSISTANT_URL'] || ENV.fetch('HA_URL', nil)
      end

      def beacon_url
        ENV.fetch('BEACON_URL', nil)
      end

      def database_url
        ENV.fetch('DATABASE_URL', 'sqlite://data/glitchcube.db')
      end

      def redis_url
        ENV.fetch('REDIS_URL', nil)
      end

      def ai_gateway_url
        ENV.fetch('AI_GATEWAY_URL', nil)
      end

      def beacon_enabled?
        !beacon_url.nil? && !beacon_url.empty?
      end

      # Database Configuration
      def database_type
        # Determine database type from DATABASE_URL or explicit setting
        db_url = database_url
        return :sqlite if db_url.start_with?('sqlite')
        return :mariadb if db_url.include?('mysql') || db_url.include?('mariadb')
        return :postgres if db_url.include?('postgres')

        :sqlite # default
      end

      def using_mariadb?
        database_type == :mariadb
      end

      def using_sqlite?
        database_type == :sqlite
      end

      def using_postgres?
        database_type == :postgres
      end

      # MariaDB specific settings (only relevant when using MariaDB)
      def mariadb_host
        return nil unless using_mariadb?

        ENV.fetch('MARIADB_HOST', 'localhost')
      end

      def mariadb_port
        return nil unless using_mariadb?

        ENV.fetch('MARIADB_PORT', '3306').to_i
      end

      def mariadb_database
        return nil unless using_mariadb?

        ENV.fetch('MARIADB_DATABASE', 'glitchcube')
      end

      def mariadb_username
        return nil unless using_mariadb?

        ENV.fetch('MARIADB_USERNAME', 'glitchcube')
      end

      def mariadb_password
        return nil unless using_mariadb?

        ENV.fetch('MARIADB_PASSWORD', 'glitchcube')
      end

      def mariadb_url
        return nil unless using_mariadb?

        "mysql2://#{mariadb_username}:#{mariadb_password}@#{mariadb_host}:#{mariadb_port}/#{mariadb_database}"
      end

      # SQLite specific settings
      def sqlite_path
        return nil unless using_sqlite?

        # Extract path from sqlite:// URL
        url = database_url
        url.sub('sqlite://', '')
      end

      # AI Configuration
      def default_ai_model
        ENV.fetch('DEFAULT_AI_MODEL', 'google/gemini-2.5-flash')
      end

      def ai_temperature
        ENV.fetch('AI_TEMPERATURE', '0.8').to_f
      end

      def ai_max_tokens
        ENV.fetch('AI_MAX_TOKENS', '200').to_i
      end

      def max_session_messages
        ENV.fetch('MAX_SESSION_MESSAGES', '10').to_i
      end

      # Device Configuration
      def device_id
        ENV.fetch('DEVICE_ID', 'glitch_cube_001')
      end

      def installation_location
        ENV.fetch('INSTALLATION_LOCATION', 'Black Rock City')
      end

      def app_version
        ENV.fetch('APP_VERSION', '1.0.0')
      end

      # GPS Configuration
      def gps_device_tracker_entity
        ENV.fetch('GPS_DEVICE_TRACKER_ENTITY', 'device_tracker.glitch_cube')
      end

      # Home camp location
      def home_camp_time
        ENV.fetch('HOME_CAMP_TIME', '5:30')
      end

      def home_camp_street
        ENV.fetch('HOME_CAMP_STREET', 'F')
      end

      def home_camp_coordinates
        # Calculate coordinates based on BRC address
        time_str = home_camp_time
        street = home_camp_street

        # Convert time to angle (2:00 = 30°, 3:00 = 60°, etc.)
        time_parts = time_str.split(':')
        hour = time_parts[0].to_i
        minute = time_parts[1].to_i

        # BRC is rotated ~30° from north, 2:00 points roughly east
        angle_degrees = (hour * 30) + (minute * 0.5) - 60 # Offset for BRC orientation
        angle_radians = angle_degrees * Math::PI / 180

        # Distance from center based on street (rough approximation)
        street_distances = {
          'Esplanade' => 0.002,
          'A' => 0.003, 'B' => 0.004, 'C' => 0.005, 'D' => 0.006,
          'E' => 0.007, 'F' => 0.008, 'G' => 0.009, 'H' => 0.010,
          'I' => 0.011, 'J' => 0.012, 'K' => 0.013, 'L' => 0.014
        }

        distance = street_distances[street] || 0.008 # Default to F street distance

        # Center Camp coordinates
        center_lat = 40.786958
        center_lng = -119.202994

        # Calculate home coordinates
        home_lat = center_lat + (distance * Math.sin(angle_radians))
        home_lng = center_lng + (distance * Math.cos(angle_radians))

        { lat: home_lat, lng: home_lng, address: "#{time_str} & #{street}" }
      end

      # System Configuration
      def port
        ENV.fetch('PORT', '4567').to_i
      end

      def timezone
        ENV.fetch('TZ', 'America/Los_Angeles')
      end

      # Logging Configuration
      def log_level
        level = ENV.fetch('LOG_LEVEL', default_log_level).upcase
        case level
        when 'DEBUG' then Logger::DEBUG
        when 'INFO' then Logger::INFO
        when 'WARN' then Logger::WARN
        when 'ERROR' then Logger::ERROR
        when 'FATAL' then Logger::FATAL
        else Logger::INFO
        end
      end

      def default_log_level
        return 'DEBUG' if development?
        return 'WARN' if test?

        'INFO'
      end

      # Deployment Settings
      def deployment_mode
        return :mac_mini if mac_mini_deployment?
        return :docker if docker_deployment?
        return :production if production?

        :development
      end

      def docker_deployment?
        File.exist?('/.dockerenv') || !ENV['DOCKER_CONTAINER'].nil?
      end

      # Configuration Validation
      def validate_production_config!
        errors = []
        errors << 'OPENROUTER_API_KEY is required' if openrouter_api_key.nil? || openrouter_api_key.empty?
        errors << 'SESSION_SECRET should be explicitly set in production' if session_secret.nil?
        errors << 'HOME_ASSISTANT_TOKEN is required' if home_assistant_token.nil? || home_assistant_token.empty?
        errors << 'HOME_ASSISTANT_URL is required' if home_assistant_url.nil? || home_assistant_url.empty?

        return if errors.empty?

        raise "Production configuration errors:\n#{errors.join("\n")}"
      end

      # Override mechanism for testing
      def override!(key, value)
        @overrides ||= {}
        @overrides[key] = value
      end

      def clear_overrides!
        @overrides = {}
      end

      def overridden?(key)
        @overrides ||= {}
        @overrides.key?(key)
      end

      private

      def env_true?(key)
        return @overrides[key.downcase.to_sym] if overridden?(key.downcase.to_sym)

        ENV[key] == 'true'
      end

      def env_value(key, default = nil)
        return @overrides[key.downcase.to_sym] if overridden?(key.downcase.to_sym)

        ENV.fetch(key, default)
      end
    end
  end
end
