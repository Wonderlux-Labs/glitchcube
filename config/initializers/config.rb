# frozen_string_literal: true

require 'ostruct'
require 'securerandom'

PROD_MINI_URL = 'http://100.104.211.107:4567'
PROD_BACKUP_MINI_URL = 'http://speedygonzo.local:4567'
SSH_MINI_USER = 'eristmini'

PROD_HASS_URL = '100.126.250.73:8123'
BACKUP_HASS_URL = 'http://glitch.local:8123'
SSH_HASS_USER = 'root'

module GlitchCube
  class ConfigBuilder
    DEFAULTS = {
      # Core Application
      openrouter_api_key: ENV.fetch('OPENROUTER_API_KEY'),
      openai_api_key: nil,
      anthropic_api_key: nil,
      helicone_api_key: ENV.fetch('HELICONE_API_KEY'),
      default_tools_model: 'qwen/qwen3-coder',
      default_model: 'z-ai/glm-4.5',
      port: 4567,
      session_secret: ENV.fetch('SESSION_SECRET', nil) || SecureRandom.hex(64),
      rack_env: ENV.fetch('RACK_ENV', 'development'),
      database_url: 'postgresql://localhost:5432/glitchcube_development',
      redis_url: 'redis://localhost:6379/0',

      # Home Assistant Integration
      home_assistant: {
        url: ENV.fetch('HOME_ASSISTANT_URL', PROD_HASS_URL),
        token: ENV.fetch('HOME_ASSISTANT_TOKEN')
      },

      # Logging and Feature Flags
      log_level: 'info',
      log_to_screen: true,
      log_file_path: nil,
      enable_circuit_breakers: false,
      enable_retries: false,

      # Monitoring
      monitoring: {
        uptime_kuma_push_url: ENV.fetch('UPTIME_KUMA_PUSH_URL', nil)
      },

      # Device/Installation Info
      device: {
        id: 'glitch_cube_001',
        location: 'Black Rock City',
        version: '1.0.0'
      },

      # System
      timezone: 'America/Los_Angeles',
      master_password: nil,
      restart_auth_token: nil,
      restart_log_file: '/tmp/glitchcube_restart.log',

      # AI Configuration
      ai: {
        temperature: 0.8,
        max_tokens: 32_000,
        max_tool_tokens: 32_000,
        max_session_messages: 10
      },

      # GPS Configuration
      gps: {
        device_tracker_entity: 'device_tracker.glitch_cube'
      },

      # Deployment Configuration
      deployment: {
        mac_mini: true,
        github_webhook_secret: nil,
        api_key: nil,
        internal_token: nil,
        hass_vm_host: 'localhost',
        hass_vm_user: 'homeassistant'
      },

      # Self-Healing Error Handler
      self_healing_mode: 'OFF',
      self_healing_min_confidence: 0.85,
      self_healing_error_threshold: 3,

      # Development/Test
      debug_mode: false,
      conversation_tracing_enabled: false
    }.freeze

    ENV_MAPPINGS = {
      openrouter_api_key: 'OPENROUTER_API_KEY',
      openai_api_key: 'OPENAI_API_KEY',
      anthropic_api_key: 'ANTHROPIC_API_KEY',
      helicone_api_key: 'HELICONE_API_KEY',
      rack_env: 'RACK_ENV',
      database_url: 'DATABASE_URL',
      redis_url: 'REDIS_URL',
      timezone: 'TZ',
      master_password: 'MASTER_PASSWORD',
      restart_auth_token: 'RESTART_AUTH_TOKEN',
      restart_log_file: 'RESTART_LOG_FILE',
      self_healing_mode: 'SELF_HEALING',
      self_healing_min_confidence: 'SELF_HEALING_MIN_CONFIDENCE',
      self_healing_error_threshold: 'SELF_HEALING_ERROR_THRESHOLD',
      debug_mode: 'DEBUG',
      conversation_tracing_enabled: 'CONVERSATION_TRACING',

      # New mappings
      log_level: 'LOG_LEVEL',
      log_to_screen: 'LOG_TO_SCREEN',
      log_file_path: 'LOG_FILE_PATH',
      enable_circuit_breakers: 'ENABLE_CIRCUIT_BREAKERS',
      enable_retries: 'ENABLE_RETRIES'
    }.freeze

    NESTED_MAPPINGS = {
      home_assistant: {
        url: %w[HOME_ASSISTANT_URL HA_URL],
        token: %w[HOME_ASSISTANT_TOKEN HA_TOKEN]
      },
      monitoring: {
        uptime_kuma_push_url: ['UPTIME_KUMA_PUSH_URL']
      },
      device: {
        id: ['DEVICE_ID'],
        location: ['INSTALLATION_LOCATION'],
        version: ['APP_VERSION']
      },
      ai: {
        default_model: ['DEFAULT_AI_MODEL'],
        default_tools_model: ['DEFAULT_TOOLS_MODEL'],
        temperature: ['AI_TEMPERATURE'],
        max_tokens: ['AI_MAX_TOKENS'],
        max_tool_tokens: ['MAX_TOOL_TOKENS'],
        max_session_messages: ['MAX_SESSION_MESSAGES']
      },
      gps: {
        device_tracker_entity: ['GPS_DEVICE_TRACKER_ENTITY']
      },
      deployment: {
        mac_mini: ['MAC_MINI_DEPLOYMENT'],
        github_webhook_secret: ['GITHUB_WEBHOOK_SECRET'],
        api_key: ['DEPLOYMENT_API_KEY'],
        internal_token: ['INTERNAL_DEPLOYMENT_TOKEN'],
        hass_vm_host: ['HASS_VM_HOST'],
        hass_vm_user: ['HASS_VM_USER']
      }
    }.freeze

    def self.build
      config = DEFAULTS.dup
      apply_environment_overrides(config)
      deep_openstruct(config)
    end

    private_class_method def self.deep_openstruct(obj)
      case obj
      when Hash
        OpenStruct.new(obj.transform_values { |v| deep_openstruct(v) })
      when Array
        obj.map { |item| deep_openstruct(item) }
      else
        obj
      end
    end

    private_class_method def self.apply_environment_overrides(config)
      # Top-level overrides
      ENV_MAPPINGS.each do |key, env_var|
        next unless ENV.key?(env_var)

        config[key] = convert_value(ENV.fetch(env_var, nil), DEFAULTS[key])
      end

      # Nested overrides
      NESTED_MAPPINGS.each do |group, mappings|
        mappings.each do |key, env_vars|
          env_vars.each do |env_var|
            if ENV.key?(env_var)
              config[group][key] = convert_value(ENV[env_var], DEFAULTS[group][key])
              break
            end
          end
        end
      end

      # Special cases
      config[:session_secret] = ENV.fetch('SESSION_SECRET', DEFAULTS[:session_secret])
      config[:helicone_api_key] = nil if config[:rack_env] == 'test'
    end

    private_class_method def self.convert_value(value, default)
      case default
      when TrueClass, FalseClass
        value == 'true'
      when Integer
        value.to_i
      when Float
        value.to_f
      else
        value
      end
    end
  end

  class Config < OpenStruct
    def self.generate_test_token
      'test-jwt-token-for-vcr-cassettes'
    end

    def self.instance
      @instance ||= new(ConfigBuilder.build.to_h)
    end

    # Validation method to ensure required configs are present
    def validate!
      errors = []
      return true if test?

      errors << 'OPENROUTER_API_KEY is required' if openrouter_api_key.nil? || openrouter_api_key.empty?

      if production?
        errors << 'SESSION_SECRET should be explicitly set in production' if ENV['SESSION_SECRET'].nil?
        errors << 'HOME_ASSISTANT_TOKEN is required' if home_assistant.url && home_assistant.token.nil?
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

    # Self-healing helper methods
    def self_healing_enabled? = self_healing_mode != 'OFF'
    def self_healing_dry_run? = self_healing_mode == 'DRY_RUN'
    def self_healing_yolo? = self_healing_mode == 'YOLO'
    def environment = rack_env
    def debug? = debug_mode

    # Environment predicates
    def development? = rack_env == 'development'
    def test? = rack_env == 'test'
    def production? = rack_env == 'production'

    # Database safety checks to prevent data loss
    def safe_to_migrate?
      return true if test?
      return false unless database_url || mariadb_url

      if production? && File.exist?('data/production/glitchcube.db')
        puts '⚠️  WARNING: Existing SQLite database detected in production!'
        puts '   Please backup your data before switching to MariaDB'
        return false
      end
      true
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

# Tool registry no longer needs initialization - tools are loaded explicitly
