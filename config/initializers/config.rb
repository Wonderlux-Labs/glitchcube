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
      openrouter_api_key: nil, # Required - will be validated
      openai_api_key: nil,
      anthropic_api_key: nil,
      helicone_api_key: nil,
      default_tools_model: 'mistralai/mistral-medium-3.1',
      default_model: 'x-ai/grok-4',
      port: 4567,
      session_secret: nil, # Auto-generated if not provided
      rack_env: 'development',
      database_url: 'postgresql://localhost:5432/glitchcube_development',
      redis_url: 'redis://localhost:6379/0',

      # Home Assistant Integration
      home_assistant: {
        url: 'http://100.126.250.73:8123', # Production HA default
        token: nil # Required - will be validated
      },

      # Logging and Feature Flags
      log_level: 'info',
      log_to_screen: true,
      log_file_path: nil,
      enable_circuit_breakers: false,
      enable_retries: false,

      # Monitoring
      monitoring: {
        uptime_kuma_push_url: 'https://status.wlux.casa/api/push/Bf8nrx6ykq'
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
        max_tokens: 4000, # More reasonable for faster responses
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
      self_healing_mode: 'DRY_RUN', # From .env.defaults
      self_healing_min_confidence: 0.85,
      self_healing_error_threshold: 2, # From .env.defaults

      # Development/Test
      debug_mode: false,
      conversation_tracing_enabled: false,

      # Tool Execution
      tool_calling_pattern: :back_to_hass, # :default or :back_to_hass
      tool_execution_mode: :conversation_extraction, # :native_tools, :back_to_hass, :conversation_extraction
      tool_retry: {
        enabled: true,
        max_iterations: 2,
        use_mcp_fallback: true
      },

      # Async Tool Configuration (Phase 5)
      enable_async_tools: true, # Feature flag for async tool execution
      async_tools: {
        immediate_response_timeout: 1.0,    # Max time for immediate acknowledgment
        background_execution_timeout: 30.0, # Max time for background tool execution
        follow_up_delay: 2.0,               # Delay before follow-up TTS
        max_concurrent_threads: 3,          # Limit concurrent async executions
        thread_cleanup_timeout: 60.0,      # Auto-cleanup thread timeout
        fallback_to_sync: true             # Fall back to sync if async fails
      },

      # Conversation Configuration
      conversation: {
        completion_timeout: 60  # Default 60 seconds for LLM calls
      },

      # Personality System
      default_personality: 'buddy' # From .env.defaults
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
      tool_calling_pattern: 'TOOL_CALLING_PATTERN',
      port: 'PORT',
      session_secret: 'SESSION_SECRET',
      default_personality: 'DEFAULT_PERSONALITY',

      # Logging and Feature Flags
      log_level: 'LOG_LEVEL',
      log_to_screen: 'LOG_TO_SCREEN',
      log_file_path: 'LOG_FILE_PATH',
      enable_circuit_breakers: 'ENABLE_CIRCUIT_BREAKERS',
      enable_retries: 'ENABLE_RETRIES',

      # Async Tools Feature Flag
      enable_async_tools: 'ENABLE_ASYNC_TOOLS'
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
      conversation: {
        completion_timeout: ['COMPLETION_TIMEOUT']
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
      },
      tool_retry: {
        enabled: ['TOOL_RETRY_ENABLED'],
        max_iterations: ['TOOL_MAX_ITERATIONS'],
        use_mcp_fallback: ['TOOL_USE_MCP_FALLBACK']
      },
      async_tools: {
        immediate_response_timeout: ['ASYNC_IMMEDIATE_TIMEOUT'],
        background_execution_timeout: ['ASYNC_BACKGROUND_TIMEOUT'],
        follow_up_delay: ['ASYNC_FOLLOW_UP_DELAY'],
        max_concurrent_threads: ['ASYNC_MAX_THREADS'],
        thread_cleanup_timeout: ['ASYNC_THREAD_CLEANUP_TIMEOUT'],
        fallback_to_sync: ['ASYNC_FALLBACK_TO_SYNC']
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
      config[:session_secret] = ENV.fetch('SESSION_SECRET', nil) || SecureRandom.hex(64)
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
      when Symbol
        value.to_sym
      else
        value
      end
    end
  end

  class Config < OpenStruct
    def self.generate_test_token
      'test-jwt-token-for-vcr-cassettes'
    end

    # Helper to safely convert ENV variables to booleans
    def self.boolean_env(env_var, default: false)
      value = ENV.fetch(env_var, nil)
      return default if value.nil? || value.empty?

      %w[true 1 yes on].include?(value.downcase)
    end

    def self.instance
      @instance ||= new(ConfigBuilder.build.to_h)
    end

    # Audit configuration for debugging and documentation
    def self.audit_defaults
      {
        defaults: ConfigBuilder::DEFAULTS,
        env_mappings: ConfigBuilder::ENV_MAPPINGS,
        nested_mappings: ConfigBuilder::NESTED_MAPPINGS,
        required_env_vars: %w[OPENROUTER_API_KEY HOME_ASSISTANT_TOKEN],
        current_env_overrides: ENV.slice(*ConfigBuilder::ENV_MAPPINGS.values),
        missing_required: check_missing_required
      }
    end

    def self.check_missing_required
      required = %w[OPENROUTER_API_KEY HOME_ASSISTANT_TOKEN]
      required.reject { |var| ENV[var]&.length&.positive? }
    end

    # Validation method to ensure required configs are present
    def validate!
      errors = []
      return true if test?

      errors << 'OPENROUTER_API_KEY is required' if openrouter_api_key.nil? || openrouter_api_key.empty?
      errors << 'HOME_ASSISTANT_TOKEN is required' if home_assistant.token.nil? || home_assistant.token.empty?

      if production? && ENV['SESSION_SECRET'].nil?
        errors << 'SESSION_SECRET should be explicitly set in production'
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

    # Async Tools Configuration Helpers
    def async_tools_enabled?
      return true unless test? || ENV.fetch('ENABLE_ASYNC_TOOLS', 'true').downcase == 'false'

      false
    end

    def async_tools_disabled? = !async_tools_enabled?
    def async_immediate_timeout = async_tools.immediate_response_timeout
    def async_background_timeout = async_tools.background_execution_timeout
    def async_follow_up_delay = async_tools.follow_up_delay
    def async_max_threads = async_tools.max_concurrent_threads
    def async_thread_cleanup_timeout = async_tools.thread_cleanup_timeout
    def async_fallback_to_sync? = async_tools.fallback_to_sync

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
