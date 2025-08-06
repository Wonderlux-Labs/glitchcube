# frozen_string_literal: true

require 'sinatra'
require 'sinatra/json'
require 'sinatra/reloader' if development?
require 'sinatra/activerecord'

# Load environment variables
if development? || test?
  require 'dotenv'
  # Load defaults first, then override with .env
  Dotenv.load('.env.defaults', '.env')
end

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

# Load application constants and config first
require_relative 'config/constants'

# Load initializers (including config.rb)
Dir[File.join(__dir__, 'config', 'initializers', '*.rb')].each { |file| require file }

# Set up database connection
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
    set :server, :puma
    set :bind, '0.0.0.0'
    set :port, GlitchCube.config.port
    # Let Puma handle binding via BIND_ALL environment variable
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
  register GlitchCube::Routes::Api::Deployment

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
    STDOUT.flush
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

  # Admin panel
  get '/admin' do
    erb :admin
  end

  # Admin API endpoints
  post '/admin/test_tts' do
    content_type :json
    
    begin
      data = JSON.parse(request.body.read)
      message = data['message'] || 'Test message from admin panel'
      entity_id = data['entity_id']
      
      ha_client = HomeAssistantClient.new
      success = ha_client.speak(message, entity_id: entity_id)
      
      { 
        success: success, 
        message: message,
        entity_id: entity_id || 'media_player.square_voice',
        timestamp: Time.now.iso8601
      }.to_json
    rescue => e
      status 500
      { 
        success: false, 
        error: e.message,
        backtrace: e.backtrace.first(5)
      }.to_json
    end
  end

  get '/admin/status' do
    content_type :json
    
    # Check various system connections
    ha_status = begin
      ha_client = HomeAssistantClient.new
      ha_client.states
      true
    rescue
      false
    end
    
    openrouter_status = begin
      OpenRouterService.available_models
      true
    rescue
      false
    end
    
    redis_status = begin
      $redis&.ping == 'PONG'
    rescue
      false
    end
    
    {
      home_assistant: ha_status,
      openrouter: openrouter_status,
      redis: redis_status,
      host_ip: Services::HostRegistrationService.new.detect_local_ip,
      ha_url: GlitchCube.config.home_assistant.url,
      ai_model: GlitchCube.config.ai.default_model
    }.to_json
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

# Register with Home Assistant on startup (Sidekiq job)
unless GlitchCube.config.home_assistant.mock_enabled
  InitialHostRegistrationWorker.perform_in(5) # 5 seconds
end

GlitchCubeApp.run! if __FILE__ == $PROGRAM_NAME
