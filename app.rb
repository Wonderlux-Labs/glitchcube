# frozen_string_literal: true

require_relative 'config/environment'

require 'sinatra'
require 'sinatra/json'
# NOTE: sinatra/reloader is deprecated - use 'rerun' gem in development instead

require 'json'
require 'sidekiq'
require 'redis'
require 'active_record'

# Load our comprehensive Sidekiq configuration strategy
require_relative 'config/sidekiq/sidekiq_config'

# Load traditional Sidekiq configuration only if running in background mode
if SidekiqConfig.sidekiq_enabled? && !SidekiqConfig.inline_mode?
  require_relative 'config/sidekiq/sidekiq'
end

# Load application configuration
require_relative 'config/constants'
require_relative 'config/database_config'

# Set up database connection using centralized config BEFORE loading initializers
# This ensures consistent database configuration across all environments
configure_database!

# Load all initializers (includes our new autoloader)
Dir[File.join(__dir__, 'config', 'initializers', '*.rb')].each { |file| require file }

# Log application startup after all initializers are loaded
Services::Logging::SimpleLogger.info(
  'Cube starting up',
  tagged: [:startup],
  environment: ENV['RACK_ENV'] || 'development',
  version: GlitchCube.config.device.version
)

# Load models
Dir[File.join(__dir__, 'app', 'models', '*.rb')].each { |file| require file }

# Load model configuration
require_relative 'config/model_presets'
require_relative 'config/model_pricing'

# All library files are now loaded by config/initializers/autoload.rb

# Load core files manually since they're ignored by Zeitwerk
Dir[File.join(__dir__, 'lib', 'core', '**', '*.rb')].each { |file| require file }

# Load routes manually since they're ignored by Zeitwerk
Dir[File.join(__dir__, 'lib', 'routes', '**', '*.rb')].each { |file| require file }

class GlitchCubeApp < Sinatra::Base
  # Include job scheduler helper for safe job scheduling
  include SidekiqConfig::JobScheduler

  configure do
    set :server, :webrick
    set :bind, '0.0.0.0'
    set :port, GlitchCube.config.port
    # Simple webrick server for single-user art installation
    enable :sessions
    set :session_secret, GlitchCube.config.session_secret

    # Track start time for uptime calculations
    GlitchCube.start_time = Time.now
  end

  configure :test do
    # Disable all protection in tests
    disable :protection
  end

  configure :development do
    # NOTE: Using rerun instead of Sinatra::Reloader for auto-reloading
    # Run with: bundle exec rerun -- bundle exec ruby app.rb
  end

  # Routes are loading correctly - diagnostics confirmed this

  # Register route modules
  # Core application routes

  # Main API routes
  register GlitchCube::Routes::Api::Gps
  register GlitchCube::Routes::Api::Conversation
  register GlitchCube::Routes::Api::Tools
  register GlitchCube::Routes::Api::Deployment
  register GlitchCube::Routes::Api::System
  register GlitchCube::Routes::Api::Entities
  register GlitchCube::Routes::Api::Proactive
  register GlitchCube::Routes::Api::LLM
  register GlitchCube::Routes::Api::Persona

  # Mount context generation route
  use Routes::Api::ContextGeneration

  # Admin routes
  register GlitchCube::Routes::Admin
  register GlitchCube::Routes::AdminScenarios
  register GlitchCube::Routes::AdminBenchmarks

  # Development-only routes (analytics, debugging, testing)
  register GlitchCube::Routes::Development::Analytics if development? || test?

  # Deployment routes (conditionally loaded for Mac Mini setup)
  register GlitchCube::Routes::Deploy if GlitchCube.config.deployment&.mac_mini && defined?(GlitchCube::Routes::Deploy)

  helpers do
    # Centralized conversation handler service
    def conversation_handler
      @conversation_handler ||= ConversationModule.new
    end

    # Helper to check if Sidekiq is available for job scheduling
    def sidekiq_available?
      SidekiqConfig.available?
    end
  end

  # Request logging for all endpoints
  before do
    @request_start_time = Time.now
    # Use debug level for high-frequency endpoints
    log_level = case request.path
                when '/health', '/health/push', '/api/v1/system/health'
                  :debug
                when %r{^/api/v1/gps/}
                  request.get? ? :debug : :info
                else
                  :info
                end

    Services::Logging::SimpleLogger.send(
      log_level,
      'Incoming request',
      tagged: %i[request incoming],
      method: request.request_method,
      path: request.path,
      ip: request.ip,
      user_agent: request.user_agent
    )
  end

  after do
    # Skip logging for static assets, favicon, and GPS polling endpoints
    return if request.path_info.start_with?('/assets', '/favicon')
    return if request.path_info.start_with?('/api/v1/gps/') && request.get?

    duration = ((@request_start_time ? Time.now - @request_start_time : 0) * 1000).round

    # Extract request parameters
    request_params = {}
    request_params.merge!(params) unless params.empty?

    # For POST requests, try to capture JSON body params
    if request.post? && request.content_type&.include?('application/json')
      # NOTE: request body may have already been read, so we'll capture what we can
      request_params['_content_type'] = request.content_type
      request_params['_content_length'] = request.content_length if request.content_length
    end

    Services::Logging::SimpleLogger.info(
      'Request completed',
      tagged: %i[request completed],
      method: request.request_method,
      path: request.path,
      status: response.status,
      duration_ms: duration,
      params: request_params,
      user_agent: request.user_agent,
      ip: request.ip
    )
  rescue StandardError => e
    # Don't let logging errors break the app
    Services::Logging::SimpleLogger.error(
      'Request logging failed',
      tagged: %i[request error],
      error: e.message,
      backtrace: e.backtrace&.first(3)
    )
  end

  get '/' do
    json({ message: 'Welcome to Glitch Cube!', status: 'online' })
  end

  get '/health' do
    # Check circuit breaker status
    circuit_status = Services::System::CircuitBreakerService.status
    overall_health = circuit_status.all? { |breaker| breaker[:state] == :closed } ? 'healthy' : 'degraded'

    json({
           status: overall_health,
           timestamp: Time.now.iso8601,
           circuit_breakers: circuit_status
         })
  end

  # Health push endpoint for Uptime Kuma monitoring
  # Reads consolidated health data from Home Assistant sensor.health_monitoring
  get '/health/push' do
    service = Services::HealthPushService.new
    result = service.push_health_status
    json(result)
  end

  not_found do
    json({ error: 'Not found', status: 404 })
  end

  error do
    json({ error: 'Internal server error', status: 500 })
  end

  # Mock HA endpoints removed - using real Home Assistant instance
end

# SimpleLogger doesn't need initialization - it's ready to use

# Check for missed deployments on startup (production only)
# Skip in development since we run production elsewhere
if ENV['RACK_ENV'] == 'production' && !test?
  begin
    Services::Logging::SimpleLogger.info('Checking for missed deployments on startup...', tagged: %i[startup deployment])

    # Fetch latest changes from remote
    git_fetch_result = system('git fetch origin main 2>/dev/null')

    if git_fetch_result
      # Check how many commits we're behind
      behind_count = `git rev-list HEAD..origin/main --count 2>/dev/null`.strip.to_i

      if behind_count.positive?
        Services::Logging::SimpleLogger.warn("Found #{behind_count} commits behind - scheduling deployment...", tagged: %i[startup deployment], behind_count: behind_count)
        Services::Logging::SimpleLogger.info('API call - startup deployment check',
                                             tagged: %i[api_call startup deployment],
                                             service: 'startup_deployment_check',
                                             endpoint: '/startup',
                                             method: 'startup',
                                             behind_count: behind_count,
                                             message: 'Missed deployments detected on startup')

        # Log for manual intervention
        Services::Logging::SimpleLogger.info("Manual deployment recommended - #{behind_count} commits behind", tagged: %i[startup deployment], behind_count: behind_count)
        Services::Logging::SimpleLogger.info("Run: curl -X POST http://localhost:#{GlitchCube.config.port}/api/v1/deploy/manual", tagged: %i[startup deployment manual])
      else
        Services::Logging::SimpleLogger.info('Repository is up to date', tagged: %i[startup deployment])
      end
    else
      Services::Logging::SimpleLogger.warn('Git fetch failed on startup - check connectivity', tagged: %i[startup deployment warning])
    end
  rescue StandardError => e
    Services::Logging::SimpleLogger.error('Startup deployment check failed', tagged: %i[startup deployment error], error: e.message, backtrace: e.backtrace&.first(3))
    Services::Logging::SimpleLogger.error('API call failed - startup deployment check',
                                          tagged: %i[api_call startup deployment error],
                                          service: 'startup_deployment_check',
                                          endpoint: '/startup',
                                          method: 'startup',
                                          status: 500,
                                          error: e.message)
  end
end

# Register with Home Assistant on startup (Sidekiq job)
if ENV['RACK_ENV'] == 'production'
  if SidekiqConfig.available?
    Jobs::HostRegistrationWorker.perform_in(5, 'initial_registration') # 5 seconds
    Services::Logging::SimpleLogger.info('Scheduled initial host registration', tagged: %i[startup jobs])
  else
    Services::Logging::SimpleLogger.warn('Sidekiq not available - skipping host registration', tagged: %i[startup jobs warning])
  end
end

# NOTE: Other startup jobs removed for testing - only host registration remains

# Start the server when running directly (not via rackup)
GlitchCubeApp.run! if __FILE__ == $PROGRAM_NAME
