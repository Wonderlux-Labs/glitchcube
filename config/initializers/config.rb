# frozen_string_literal: true

require 'ostruct'

module GlitchCube
  class Config < OpenStruct
    def self.instance
      @instance ||= new(
        # Core Application
        openrouter_api_key: ENV.fetch('OPENROUTER_API_KEY', nil),
        openai_api_key: ENV.fetch('OPENAI_API_KEY', nil),
        anthropic_api_key: ENV.fetch('ANTHROPIC_API_KEY', nil),
        helicone_api_key: ENV.fetch('HELICONE_API_KEY', nil),
        default_ai_model: ENV.fetch('DEFAULT_AI_MODEL', 'google/gemini-2.5-flash'),
        port: ENV.fetch('PORT', '4567').to_i,
        session_secret: ENV.fetch('SESSION_SECRET') { SecureRandom.hex(64) },
        rack_env: ENV.fetch('RACK_ENV', 'development'),
        database_url: ENV.fetch('DATABASE_URL', 'postgresql://localhost:5432/glitchcube_development'),
        redis_url: ENV.fetch('REDIS_URL', nil),

        # MariaDB Configuration
        mariadb: OpenStruct.new(
          host: ENV.fetch('MARIADB_HOST', 'localhost'),
          port: ENV.fetch('MARIADB_PORT', '3306').to_i,
          database: ENV.fetch('MARIADB_DATABASE', 'glitchcube'),
          username: ENV.fetch('MARIADB_USERNAME', 'glitchcube'),
          password: ENV.fetch('MARIADB_PASSWORD', 'glitchcube'),
          url: build_mariadb_url
        ),

        # Home Assistant Integration
        home_assistant: OpenStruct.new(
          url: ENV['HOME_ASSISTANT_URL'] || ENV.fetch('HA_URL', nil),
          token: ENV['HOME_ASSISTANT_TOKEN'] || ENV.fetch('HA_TOKEN', nil),
          mock_enabled: ENV['MOCK_HOME_ASSISTANT'] == 'true'
        ),

        # Beacon Service
        beacon: OpenStruct.new(
          url: ENV.fetch('BEACON_URL', nil),
          token: ENV.fetch('BEACON_TOKEN', nil),
          enabled: !ENV['BEACON_URL'].nil? && !ENV['BEACON_URL'].empty?
        ),

        # Device/Installation Info
        device: OpenStruct.new(
          id: ENV.fetch('DEVICE_ID', 'glitch_cube_001'),
          location: ENV.fetch('INSTALLATION_LOCATION', 'Black Rock City'),
          version: ENV.fetch('APP_VERSION', '1.0.0')
        ),

        # System
        timezone: ENV.fetch('TZ', 'America/Los_Angeles'),
        master_password: ENV.fetch('MASTER_PASSWORD', nil),

        # AI Conversation Parameters
        conversation: OpenStruct.new(
          temperature: ENV.fetch('AI_TEMPERATURE', '0.8').to_f,
          max_tokens: ENV.fetch('AI_MAX_TOKENS', '200').to_i,
          max_session_messages: ENV.fetch('MAX_SESSION_MESSAGES', '10').to_i
        ),

        # GPS Configuration
        gps: OpenStruct.new(
          device_tracker_entity: ENV.fetch('GPS_DEVICE_TRACKER_ENTITY', 'device_tracker.glitch_cube')
        ),

        # Deployment Configuration
        deployment: OpenStruct.new(
          mac_mini: ENV.fetch('MAC_MINI_DEPLOYMENT', 'true') == 'true'
        ),

        # Development/Test
        development?: ENV['RACK_ENV'] == 'development',
        test?: ENV['RACK_ENV'] == 'test',
        production?: ENV['RACK_ENV'] == 'production'
      )
    end

    # Validation method to ensure required configs are present
    def validate!
      errors = []

      # Always required for core functionality
      errors << 'OPENROUTER_API_KEY is required - please add to .env file' if openrouter_api_key.nil? || openrouter_api_key.empty?
      
      # Required in production
      if production?
        errors << 'SESSION_SECRET should be explicitly set in production' if ENV['SESSION_SECRET'].nil?

        errors << 'HOME_ASSISTANT_TOKEN is required when not using mock' if home_assistant.url && !home_assistant.mock_enabled && home_assistant.token.nil?

        errors << 'BEACON_TOKEN is required when BEACON_URL is set' if beacon.enabled && beacon.token.nil?
      end

      raise "Configuration errors:\n#{errors.join("\n")}" unless errors.empty?

      true
    end

    # Helper to get Redis connection
    def redis_connection
      return nil unless redis_url

      require 'redis'
      @redis_connection ||= Redis.new(url: redis_url)
    end

    # Helper to check if persistence is available
    def persistence_enabled?
      !database_url.nil?
    end

    # Helper to get MariaDB URL (with fallback)
    def mariadb_url
      return mariadb.url if mariadb.url && !mariadb.url.empty?
      return nil unless mariadb_available?

      "mysql2://#{mariadb.username}:#{mariadb.password}@#{mariadb.host}:#{mariadb.port}/#{mariadb.database}?encoding=utf8mb4"
    end

    # Check if MariaDB connection is available (without destroying data)
    def mariadb_available?
      return false unless mariadb.host && mariadb.username && mariadb.password

      # In test environment, always use SQLite for safety
      return false if test?

      # Only attempt connection if we have all required parameters
      true
    end

    # Database safety checks to prevent data loss
    def safe_to_migrate?
      return true if test? # Always safe in test with in-memory SQLite

      # Check if we're switching database types
      current_db = database_url || mariadb_url
      return false unless current_db

      # Don't migrate if we detect existing SQLite data in production
      if production? && File.exist?('data/production/glitchcube.db')
        puts '⚠️  WARNING: Existing SQLite database detected in production!'
        puts '   Please backup your data before switching to MariaDB'
        return false
      end

      true
    end

    def self.build_mariadb_url
      host = ENV.fetch('MARIADB_HOST', 'localhost')
      port = ENV.fetch('MARIADB_PORT', '3306')
      database = ENV.fetch('MARIADB_DATABASE', 'glitchcube')
      username = ENV.fetch('MARIADB_USERNAME', 'glitchcube')
      password = ENV.fetch('MARIADB_PASSWORD', 'glitchcube')

      return nil if ENV.fetch('MARIADB_ENABLED', 'false') != 'true'

      "mysql2://#{username}:#{password}@#{host}:#{port}/#{database}?encoding=utf8mb4"
    end
  end

  # Convenience method
  def self.config
    Config.instance
  end
end

# Initialize and validate configuration
begin
  GlitchCube.config.validate!
  puts '✅ Configuration loaded successfully'
rescue StandardError => e
  puts "❌ Configuration error: #{e.message}"
  raise if ENV['RACK_ENV'] == 'production'
end
