# frozen_string_literal: true

require 'ostruct'
require 'securerandom'

# =============================================================================
# GLITCHCUBE ENVIRONMENT VARIABLE REFERENCE
# =============================================================================
#
# REQUIRED:
#   OPENROUTER_API_KEY       - Primary AI provider API key
#   HOME_ASSISTANT_TOKEN     - Home Assistant long-lived access token
#
# OPTIONAL CORE:
#   RACK_ENV                 - Application environment (development/test/production)
#   DATABASE_URL             - PostgreSQL connection string
#   REDIS_URL                - Redis connection string
#   PORT                     - Web server port (default: 4567)
#   SESSION_SECRET           - Session encryption key (auto-generated if not set)
#   TZ                       - Timezone (default: America/Los_Angeles)
#
# OPTIONAL AI:
#   DEFAULT_AI_MODEL         - Default LLM model (default: x-ai/grok-4)
#   DEFAULT_TOOLS_MODEL      - Tools-specific model (default: mistralai/mistral-medium-3.1)
#   AI_TEMPERATURE           - Response creativity (default: 0.8)
#   AI_MAX_TOKENS            - Max response tokens (default: 4000)
#   MAX_TOOL_TOKENS          - Max tool execution tokens (default: 32000)
#   MAX_SESSION_MESSAGES     - Max conversation history (default: 10)
#   COMPLETION_TIMEOUT       - LLM call timeout seconds (default: 60)
#
# OPTIONAL HOME ASSISTANT:
#   HOME_ASSISTANT_URL       - HA instance URL (aliases: HA_URL)
#   GPS_DEVICE_TRACKER_ENTITY - GPS tracking entity (default: device_tracker.glitch_cube)
#
# OPTIONAL DEPLOYMENT:
#   MAC_MINI_DEPLOYMENT      - Running on Mac Mini hardware (default: false)
#   GITHUB_WEBHOOK_SECRET    - GitHub webhook validation secret
#   DEPLOYMENT_API_KEY       - Deployment API authentication
#   INTERNAL_DEPLOYMENT_TOKEN - Internal deployment token
#   HASS_VM_HOST             - Home Assistant VM host (default: localhost)
#   HASS_VM_USER             - Home Assistant VM user (default: homeassistant)
#
# OPTIONAL DEVICE INFO:
#   DEVICE_ID                - Unique device identifier (default: glitch_cube_001)
#   INSTALLATION_LOCATION    - Physical location (default: Black Rock City)
#   APP_VERSION              - Application version (default: 1.0.0)
#
# OPTIONAL MONITORING:
#   UPTIME_KUMA_PUSH_URL     - Uptime monitoring webhook URL
#
# OPTIONAL FEATURES:
#   DEFAULT_PERSONALITY      - Default persona (default: buddy)
#   DEBUG                    - Enable debug mode (default: false)
#   CONVERSATION_TRACING     - Enable conversation tracing (default: false)
#   ENABLE_ASYNC_TOOLS       - Enable async tool execution (default: true)
#
# OPTIONAL SELF-HEALING:
#   SELF_HEALING             - Self-healing mode: OFF/DRY_RUN/YOLO (default: DRY_RUN)
#   SELF_HEALING_MIN_CONFIDENCE - Min confidence for healing (default: 0.85)
#   SELF_HEALING_ERROR_THRESHOLD - Error threshold for healing (default: 2)
#
# OPTIONAL ASYNC TOOLS:
#   ASYNC_IMMEDIATE_TIMEOUT  - Immediate response timeout (default: 30s)
#   ASYNC_BACKGROUND_TIMEOUT - Background execution timeout (default: 30s)
#   ASYNC_FOLLOW_UP_DELAY    - Follow-up delay (default: 0s)
#   ASYNC_MAX_THREADS        - Max concurrent threads (default: 10)
#   ASYNC_THREAD_CLEANUP_TIMEOUT - Thread cleanup timeout (default: 60s)
#   ASYNC_FALLBACK_TO_SYNC   - Fallback to sync mode (default: true)
#
# OPTIONAL TOOL RETRY:
#   TOOL_RETRY_ENABLED       - Enable tool retry (default: true)
#   TOOL_MAX_ITERATIONS      - Max retry iterations (default: 2)
#   TOOL_USE_MCP_FALLBACK    - Use MCP fallback (default: true)
#
# OPTIONAL LOGGING:
#   LOG_LEVEL                - Logging level (default: info)
#   LOG_TO_SCREEN            - Log to console (default: true)
#   LOG_FILE_PATH            - Log file path (default: nil)
#
# OPTIONAL SECURITY:
#   MASTER_PASSWORD          - Master authentication password
#   RESTART_AUTH_TOKEN       - Restart endpoint authentication
#   RESTART_LOG_FILE         - Restart log file (default: /tmp/glitchcube_restart.log)
#
# OPTIONAL THIRD-PARTY:
#   OPENAI_API_KEY           - OpenAI API key (if using directly)
#   ANTHROPIC_API_KEY        - Anthropic API key (if using directly)
#   HELICONE_API_KEY         - Helicone monitoring key
#
# =============================================================================

module GlitchCube
  class ConfigBuilder
    DEFAULTS = {
      # Core Application
      openrouter_api_key: nil, # Required - will be validated
      openai_api_key: nil,
      anthropic_api_key: nil,
      helicone_api_key: nil,
      port: 4567,
      session_secret: nil, # Auto-generated if not provided
      rack_env: 'development',
      database_url: 'postgresql://localhost:5432/glitchcube_development',
      redis_url: 'redis://localhost:6379/0',
      timezone: 'America/Los_Angeles',
      master_password: nil,
      restart_auth_token: nil,
      restart_log_file: '/tmp/glitchcube_restart.log',

      # Home Assistant Integration
      home_assistant: {
        url: 'http://100.126.250.73:8123', # Production HA default
        token: nil # Required - will be validated
      },

      # AI Configuration
      ai: {
        default_model: 'x-ai/grok-4',
        default_tools_model: 'mistralai/mistral-medium-3.1',
        temperature: 0.8,
        max_tokens: 4000,
        max_tool_tokens: 32_000,
        max_session_messages: 10
      },

      # Conversation Configuration
      conversation: {
        completion_timeout: 60  # Default 60 seconds for LLM calls
      },

      # GPS Configuration
      gps: {
        device_tracker_entity: 'device_tracker.glitch_cube'
      },

      # Device/Installation Info
      device: {
        id: 'glitch_cube_001',
        location: 'Black Rock City',
        version: '1.0.0'
      },

      # Monitoring
      monitoring: {
        uptime_kuma_push_url: 'https://status.wlux.casa/api/push/Bf8nrx6ykq'
      },

      # Deployment Configuration
      deployment: {
        mac_mini: false, # Changed from true to false as default
        github_webhook_secret: nil,
        api_key: nil,
        internal_token: nil,
        hass_vm_host: 'localhost',
        hass_vm_user: 'homeassistant'
      },

      # Feature Flags
      debug_mode: false,
      conversation_tracing_enabled: false,
      enable_async_tools: true,
      default_personality: 'buddy',

      # Self-Healing Error Handler
      self_healing_mode: 'DRY_RUN',
      self_healing_min_confidence: 0.85,
      self_healing_error_threshold: 2,

      # Tool Execution
      tool_retry: {
        enabled: true,
        max_iterations: 2,
        use_mcp_fallback: true
      },

      # Async Tool Configuration
      async_tools: {
        immediate_response_timeout: 30,
        background_execution_timeout: 30,
        follow_up_delay: 0,
        max_concurrent_threads: 10,
        thread_cleanup_timeout: 60.0,
        fallback_to_sync: true
      },

      # Logging
      log_level: 'info',
      log_to_screen: true,
      log_file_path: nil
    }.freeze

    ENV_MAPPINGS = {
      # Core Application
      openrouter_api_key: 'OPENROUTER_API_KEY',
      openai_api_key: 'OPENAI_API_KEY',
      anthropic_api_key: 'ANTHROPIC_API_KEY',
      helicone_api_key: 'HELICONE_API_KEY',
      rack_env: 'RACK_ENV',
      database_url: 'DATABASE_URL',
      redis_url: 'REDIS_URL',
      port: 'PORT',
      session_secret: 'SESSION_SECRET',
      timezone: 'TZ',
      master_password: 'MASTER_PASSWORD',
      restart_auth_token: 'RESTART_AUTH_TOKEN',
      restart_log_file: 'RESTART_LOG_FILE',

      # Feature Flags
      debug_mode: 'DEBUG',
      conversation_tracing_enabled: 'CONVERSATION_TRACING',
      enable_async_tools: 'ENABLE_ASYNC_TOOLS',
      default_personality: 'DEFAULT_PERSONALITY',

      # Self-Healing
      self_healing_mode: 'SELF_HEALING',
      self_healing_min_confidence: 'SELF_HEALING_MIN_CONFIDENCE',
      self_healing_error_threshold: 'SELF_HEALING_ERROR_THRESHOLD',

      # Logging
      log_level: 'LOG_LEVEL',
      log_to_screen: 'LOG_TO_SCREEN',
      log_file_path: 'LOG_FILE_PATH'
    }.freeze

    NESTED_MAPPINGS = {
      home_assistant: {
        url: %w[HOME_ASSISTANT_URL HA_URL],
        token: %w[HOME_ASSISTANT_TOKEN HA_TOKEN]
      },
      ai: {
        default_model: %w[DEFAULT_AI_MODEL],
        default_tools_model: %w[DEFAULT_TOOLS_MODEL],
        temperature: %w[AI_TEMPERATURE],
        max_tokens: %w[AI_MAX_TOKENS],
        max_tool_tokens: %w[MAX_TOOL_TOKENS],
        max_session_messages: %w[MAX_SESSION_MESSAGES]
      },
      conversation: {
        completion_timeout: %w[COMPLETION_TIMEOUT]
      },
      gps: {
        device_tracker_entity: %w[GPS_DEVICE_TRACKER_ENTITY]
      },
      device: {
        id: %w[DEVICE_ID],
        location: %w[INSTALLATION_LOCATION],
        version: %w[APP_VERSION]
      },
      monitoring: {
        uptime_kuma_push_url: %w[UPTIME_KUMA_PUSH_URL]
      },
      deployment: {
        mac_mini: %w[MAC_MINI_DEPLOYMENT],
        github_webhook_secret: %w[GITHUB_WEBHOOK_SECRET],
        api_key: %w[DEPLOYMENT_API_KEY],
        internal_token: %w[INTERNAL_DEPLOYMENT_TOKEN],
        hass_vm_host: %w[HASS_VM_HOST],
        hass_vm_user: %w[HASS_VM_USER]
      },
      tool_retry: {
        enabled: %w[TOOL_RETRY_ENABLED],
        max_iterations: %w[TOOL_MAX_ITERATIONS],
        use_mcp_fallback: %w[TOOL_USE_MCP_FALLBACK]
      },
      async_tools: {
        immediate_response_timeout: %w[ASYNC_IMMEDIATE_TIMEOUT],
        background_execution_timeout: %w[ASYNC_BACKGROUND_TIMEOUT],
        follow_up_delay: %w[ASYNC_FOLLOW_UP_DELAY],
        max_concurrent_threads: %w[ASYNC_MAX_THREADS],
        thread_cleanup_timeout: %w[ASYNC_THREAD_CLEANUP_TIMEOUT],
        fallback_to_sync: %w[ASYNC_FALLBACK_TO_SYNC]
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
              config[group][key] = convert_value(ENV.fetch(env_var, nil), DEFAULTS[group][key])
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
      required.reject { |var| ENV.fetch(var, nil)&.length&.positive? }
    end

    # Validation method to ensure required configs are present
    def validate!
      errors = []
      return true if test?

      errors << 'OPENROUTER_API_KEY is required' if openrouter_api_key.nil? || openrouter_api_key.empty?
      errors << 'HOME_ASSISTANT_TOKEN is required' if home_assistant.token.nil? || home_assistant.token.empty?

      if production? && ENV.fetch('SESSION_SECRET', nil).nil?
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

    # AI Configuration Helpers (convenience methods for common access patterns)
    def default_model = ai.default_model
    def default_tools_model = ai.default_tools_model
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
  raise if ENV.fetch('RACK_ENV', 'development') == 'production'
end
