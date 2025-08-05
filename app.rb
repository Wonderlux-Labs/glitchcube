# frozen_string_literal: true

require 'sinatra'
require 'sinatra/json'
require 'sinatra/reloader' if development?

# Load environment variables
if development? || test?
  require 'dotenv'
  # Load defaults first, then override with .env
  Dotenv.load('.env.defaults', '.env')
end

require 'desiru'
require 'json'
require 'sidekiq'
require 'redis'

# Load patches for gem compatibility issues
require_relative 'lib/patches/desiru_openrouter_errors'

# Load circuit breaker service
require_relative 'lib/services/circuit_breaker_service'

# Load logger service
require_relative 'lib/services/logger_service'

# Load database startup service
require_relative 'lib/services/database_startup_service'

# Load application constants and config first
require_relative 'config/constants'

# Load initializers (including config.rb)
Dir[File.join(__dir__, 'config', 'initializers', '*.rb')].each { |file| require file }

# Ensure databases are ready on app startup
Services::DatabaseStartupService.ensure_databases_ready!

# Configure Desiru with OpenRouter
Desiru.configure do |config|
  config.default_model = Desiru::Models::OpenRouter.new(
    api_key: GlitchCube.config.openrouter_api_key,
    model: GlitchCube.config.default_ai_model
  )
end

# Configure persistence (optional - will work without it)
require_relative 'config/persistence'
GlitchCube::Persistence.configure!

Dir[File.join(__dir__, 'lib', 'modules', '*.rb')].each { |file| require file }
Dir[File.join(__dir__, 'lib', 'tools', '*.rb')].each { |file| require file }
Dir[File.join(__dir__, 'lib', 'jobs', '*.rb')].each { |file| require file }
Dir[File.join(__dir__, 'lib', 'services', '*.rb')].each { |file| require file }
Dir[File.join(__dir__, 'lib', 'routes', '*.rb')].each { |file| require file }
Dir[File.join(__dir__, 'lib', 'routes', '**', '*.rb')].each { |file| require file }

class GlitchCubeApp < Sinatra::Base
  configure do
    set :server, :puma
    set :port, GlitchCube.config.port
    enable :sessions
    set :session_secret, GlitchCube.config.session_secret
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
  
  # Development-only routes (analytics, debugging, testing)
  if development? || test?
    register GlitchCube::Routes::Development::Analytics
  end
  
  # Deployment routes (conditionally loaded for Mac Mini setup)
  if GlitchCube.config.deployment&.mac_mini && defined?(GlitchCube::Routes::Deploy)
    register GlitchCube::Routes::Deploy
  end

  helpers do
    # Centralized conversation handler service
    def conversation_handler
      @conversation_handler ||= Services::ConversationHandlerService.new
    end
  end

  # Request logging for all endpoints
  before do
    @request_start_time = Time.now
  end

  after do
    # Skip logging for static assets and favicon
    return if request.path_info.start_with?('/assets', '/favicon')

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

GlitchCubeApp.run! if __FILE__ == $PROGRAM_NAME
