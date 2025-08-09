# frozen_string_literal: true

require_relative 'config/environment'

require 'sinatra'
require 'sinatra/json'
# Note: sinatra/reloader is deprecated - use 'rerun' gem in development instead

require 'sinatra/activerecord'

require 'json'
require 'sidekiq'
require 'redis'
require 'active_record'

# Load Sidekiq configuration with cron job logging
require_relative 'config/sidekiq' if defined?(Sidekiq)

# Load services

# Load circuit breaker service
require_relative 'lib/services/circuit_breaker_service'

# Load logger service
require_relative 'lib/services/logger_service'

# Load health monitoring services
require_relative 'lib/services/health_push_service'

# Load entity management services
require_relative 'lib/services/entity_manager_service'

# Load application constants and config first
require_relative 'config/constants'

# Load database configuration first
require_relative 'config/database_config'

# Load initializers (including config.rb)
Dir[File.join(__dir__, 'config', 'initializers', '*.rb')].each { |file| require file }

# Set up database connection using centralized config
# This ensures consistent database configuration across all environments
configure_database!
set :database_file, 'config/database.yml'

# Load models
Dir[File.join(__dir__, 'app', 'models', '*.rb')].each { |file| require file }

# Load model pricing
require_relative 'config/model_pricing'

Dir[File.join(__dir__, 'lib', 'modules', '*.rb')].each { |file| require file }
Dir[File.join(__dir__, 'lib', 'tools', '*.rb')].each { |file| require file }
Dir[File.join(__dir__, 'lib', 'jobs', '*.rb')].each { |file| require file }
Dir[File.join(__dir__, 'lib', 'services', '*.rb')].each { |file| require file }
Dir[File.join(__dir__, 'lib', 'routes', '*.rb')].each { |file| require file }
Dir[File.join(__dir__, 'lib', 'routes', '**', '*.rb')].each { |file| require file }

class GlitchCubeApp < Sinatra::Base
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
    register Sinatra::Reloader
  end

  # Register route modules
  # Core application routes
  register GlitchCube::Routes::Core::Kiosk

  # Main API routes
  register GlitchCube::Routes::Api::Gps
  register GlitchCube::Routes::Api::Conversation
  register GlitchCube::Routes::Api::Tools
  register GlitchCube::Routes::Api::Deployment
  register GlitchCube::Routes::Api::System
  register GlitchCube::Routes::Api::Entities
  register GlitchCube::Routes::Api::Proactive

  # Admin routes
  register GlitchCube::Routes::Admin
  register GlitchCube::Routes::AdminTest

  # Development-only routes (analytics, debugging, testing)
  register GlitchCube::Routes::Development::Analytics if development? || test?

  # Deployment routes (conditionally loaded for Mac Mini setup)
  register GlitchCube::Routes::Deploy if GlitchCube.config.deployment&.mac_mini && defined?(GlitchCube::Routes::Deploy)

  helpers do
    # Centralized conversation handler service
    def conversation_handler
      @conversation_handler ||= Services::ConversationHandlerService.new
    end
  end

  # Request logging for all endpoints
  before do
    @request_start_time = Time.now
    # Immediate debug logging for connection troubleshooting
    puts "🔍 INCOMING REQUEST: #{request.request_method} #{request.path} from #{request.ip} (#{request.user_agent})"
    $stdout.flush
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

    Services::LoggerService.log_request(
      method: request.request_method,
      path: request.path,
      status: response.status,
      duration: duration,
      params: request_params,
      user_agent: request.user_agent,
      ip: request.ip
    )
  rescue StandardError => e
    # Don't let logging errors break the app
    puts "Request logging error: #{e.message}"
  end

  get '/' do
    json({ message: 'Welcome to Glitch Cube!', status: 'online' })
  end

  get '/health' do
    # Check circuit breaker status
    circuit_status = Services::CircuitBreakerService.status
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

# Initialize logger service after app is defined
Services::LoggerService.setup_loggers

# Check for missed deployments on startup (production only)
# Skip in development since we run production elsewhere
if ENV['RACK_ENV'] == 'production' && !test?
  begin
    puts '🔍 Checking for missed deployments on startup...'

    # Fetch latest changes from remote
    git_fetch_result = system('git fetch origin main 2>/dev/null')

    if git_fetch_result
      # Check how many commits we're behind
      behind_count = `git rev-list HEAD..origin/main --count 2>/dev/null`.strip.to_i

      if behind_count.positive?
        puts "⚠️ Found #{behind_count} commits behind - scheduling deployment..."
        Services::LoggerService.log_api_call(
          service: 'startup_deployment_check',
          endpoint: '/startup',
          method: 'startup',
          behind_count: behind_count,
          message: 'Missed deployments detected on startup'
        )

        # Schedule deployment in background (after full startup)
        # Use Sidekiq if available, otherwise log for manual intervention
        if defined?(Sidekiq) && Sidekiq.redis_info
          # Get latest commit info for deployment
          latest_commit = `git rev-parse origin/main 2>/dev/null`.strip
          latest_message = `git log origin/main -1 --pretty=%B 2>/dev/null`.strip

          deployment_info = {
            repository: 'glitchcube',
            branch: 'main',
            commit_sha: latest_commit,
            commit_message: latest_message,
            committer: 'startup_recovery',
            timestamp: Time.now.iso8601
          }

          # Schedule deployment worker to run in 10 seconds (after full startup)
          MissedDeploymentWorker.perform_in(10, deployment_info)
          puts "📋 Scheduled deployment worker for #{behind_count} missed commits"
        else
          puts "📋 Manual deployment recommended - #{behind_count} commits behind"
          puts "💡 Run: curl -X POST http://localhost:#{GlitchCube.config.port}/api/v1/deploy/manual"
        end
      else
        puts '✅ Repository is up to date'
      end
    else
      puts '⚠️ Git fetch failed on startup - check connectivity'
    end
  rescue StandardError => e
    puts "❌ Startup deployment check failed: #{e.message}"
    Services::LoggerService.log_api_call(
      service: 'startup_deployment_check',
      endpoint: '/startup',
      method: 'startup',
      status: 500,
      error: e.message
    )
  end
end

# Register with Home Assistant on startup (Sidekiq job)
if ENV['RACK_ENV'] == 'production'
  InitialHostRegistrationWorker.perform_in(5) # 5 seconds
end

# Start the server when running directly (not via rackup)
GlitchCubeApp.run! if __FILE__ == $PROGRAM_NAME
