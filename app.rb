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

# Load application constants and config first
require_relative 'config/constants'

# Load initializers (including config.rb)
Dir[File.join(__dir__, 'config', 'initializers', '*.rb')].each { |file| require file }

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

  configure do
    # Enable mock HA when explicitly requested
    set :mock_ha_enabled, GlitchCube.config.home_assistant.mock_enabled
  end

  helpers do
    def conversation_module
      @conversation_module ||= ConversationModule.new
    end

    def tool_agent
      # Create a ReAct agent with our test tool
      @tool_agent ||= Desiru::Modules::ReAct.new(
        'question -> answer: string',
        tools: [TestTool],
        max_iterations: 3
      )
    end

    def home_assistant_agent
      # Create a ReAct agent with both test tool and HA tool
      @home_assistant_agent ||= Desiru::Modules::ReAct.new(
        'request -> response: string',
        tools: [TestTool, HomeAssistantTool],
        max_iterations: 5
      )
    end
  end

  # Initialize logger service
  Services::LoggerService.setup_loggers

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
           version: GlitchCube.config.app.version,
           environment: GlitchCube.config.app.environment,
           circuit_breakers: circuit_status
         })
  end

  post '/api/v1/test' do
    content_type :json

    begin
      request_body = JSON.parse(request.body.read)
      message = request_body['message'] || 'Hello, Glitch Cube!'

      # Use the conversation module with Desiru
      result = conversation_module.call(
        message: message,
        context: request_body['context'] || {}
      )

      json({
             success: true,
             response: result[:response],
             timestamp: Time.now.iso8601
           })
    rescue StandardError => e
      status 500
      json({
             success: false,
             error: e.message,
             timestamp: Time.now.iso8601
           })
    end
  end

  post '/api/v1/conversation' do
    content_type :json

    begin
      request_body = JSON.parse(request.body.read)

      # Add session ID to context if not present
      context = request_body['context'] || {}
      context[:session_id] ||= request.session[:session_id] || SecureRandom.uuid

      result = conversation_module.call(
        message: request_body['message'],
        context: context,
        mood: request_body['mood'] || 'neutral'
      )

      json({
             success: true,
             data: result,
             timestamp: Time.now.iso8601
           })
    rescue StandardError => e
      status 400
      json({
             success: false,
             error: e.message
           })
    end
  end

  # RAG-enhanced conversation endpoint
  post '/api/v1/conversation/with_context' do
    content_type :json

    begin
      request_body = JSON.parse(request.body.read)
      message = request_body['message']

      # Use RAG to get relevant context
      require_relative 'lib/services/context_retrieval_service'
      rag = Services::SimpleRAG.new
      rag_result = rag.answer_with_context(message)

      # Enhance the response with context
      context = request_body['context'] || {}
      context[:rag_contexts] = rag_result[:contexts_used]
      context[:session_id] ||= request.session[:session_id] || SecureRandom.uuid

      # Get conversation response
      conv_result = conversation_module.call(
        message: message,
        context: context,
        mood: request_body['mood'] || 'neutral'
      )

      # Combine RAG and conversation results
      json({
             success: true,
             data: {
               response: conv_result[:response],
               suggested_mood: conv_result[:suggested_mood],
               confidence: [conv_result[:confidence], rag_result[:confidence]].max,
               contexts_used: rag_result[:contexts_used]
             },
             timestamp: Time.now.iso8601
           })
    rescue StandardError => e
      status 400
      json({
             success: false,
             error: e.message
           })
    end
  end

  # Tool test endpoint using ReAct pattern
  post '/api/v1/tool_test' do
    content_type :json

    begin
      request_body = JSON.parse(request.body.read)
      message = request_body['message'] || 'Tell me about the battery status'

      # Use the ReAct agent
      result = tool_agent.call(question: message)

      json({
             success: true,
             response: result[:answer],
             timestamp: Time.now.iso8601
           })
    rescue StandardError => e
      status 500
      json({
             success: false,
             error: e.message,
             backtrace: e.backtrace[0..5]
           })
    end
  end

  # Home Assistant integration endpoint
  post '/api/v1/home_assistant' do
    content_type :json

    begin
      request_body = JSON.parse(request.body.read)
      message = request_body['message'] || 'Check all sensors and set the light to blue'

      # Use the HA-enabled ReAct agent
      result = home_assistant_agent.call(request: message)

      json({
             success: true,
             response: result[:response],
             timestamp: Time.now.iso8601
           })
    rescue StandardError => e
      status 500
      json({
             success: false,
             error: e.message,
             backtrace: e.backtrace[0..5]
           })
    end
  end

  # Error statistics endpoint (development and test only)
  if development? || test?
    get '/api/v1/logs/errors' do
      content_type :json
      
      json({
             error_summary: Services::LoggerService.error_summary,
             error_stats: Services::LoggerService.error_stats
           })
    end

    get '/api/v1/logs/circuit_breakers' do
      content_type :json
      
      json({
             circuit_breakers: Services::CircuitBreakerService.status,
             actions: {
               reset_all: '/api/v1/logs/circuit_breakers/reset',
               reset_single: '/api/v1/logs/circuit_breakers/:name/reset'
             }
           })
    end

    post '/api/v1/logs/circuit_breakers/reset' do
      Services::CircuitBreakerService.reset_all
      json({ message: 'All circuit breakers reset', status: 'success' })
    end
  end

  # Analytics endpoints (development and test only)
  if development? || test?
    get '/api/v1/analytics/conversations' do
      content_type :json

      limit = params[:limit]&.to_i || 10
      history = GlitchCube::Persistence.get_conversation_history(limit: limit)

      json({
             success: true,
             count: history.length,
             conversations: history
           })
    end

    # System prompt preview endpoint
    get '/api/v1/system_prompt/:character?' do
      content_type :json

      require_relative 'lib/services/system_prompt_service'

      character = params[:character]
      context = {
        location: params[:location] || 'Default Location',
        battery_level: params[:battery] || '100%',
        interaction_count: params[:count]&.to_i || 1
      }

      prompt_service = Services::SystemPromptService.new(
        character: character,
        context: context
      )

      json({
             success: true,
             character: character || 'default',
             prompt: prompt_service.generate,
             timestamp: Time.now.iso8601
           })
    end

    get '/api/v1/analytics/modules/:module_name' do
      content_type :json

      analytics = GlitchCube::Persistence.get_module_analytics(params[:module_name])

      json({
             success: true,
             module: params[:module_name],
             analytics: analytics
           })
    end

    # Context document management endpoints
    get '/api/v1/context/documents' do
      content_type :json

      require_relative 'lib/services/context_retrieval_service'
      service = Services::ContextRetrievalService.new

      json({
             success: true,
             documents: service.list_documents
           })
    end

    post '/api/v1/context/documents' do
      content_type :json

      begin
        data = JSON.parse(request.body.read)

        require_relative 'lib/services/context_retrieval_service'
        service = Services::ContextRetrievalService.new

        success = service.add_document(
          data['filename'],
          data['content'],
          data['metadata'] || {}
        )

        json({
               success: success,
               message: success ? 'Document added successfully' : 'Failed to add document'
             })
      rescue StandardError => e
        status 400
        json({
               success: false,
               error: e.message
             })
      end
    end

    # Test context retrieval
    post '/api/v1/context/search' do
      content_type :json

      begin
        data = JSON.parse(request.body.read)

        require_relative 'lib/services/context_retrieval_service'
        service = Services::ContextRetrievalService.new

        results = service.retrieve_context(data['query'], k: data['k'] || 3)

        json({
               success: true,
               query: data['query'],
               results: results
             })
      rescue StandardError => e
        status 400
        json({
               success: false,
               error: e.message
             })
      end
    end

    # Beacon management endpoints
    get '/api/v1/beacon/status' do
      content_type :json

      require_relative 'lib/services/beacon_service'
      Services::BeaconService.new

      # Get last heartbeat info from Redis if available
      last_heartbeat = GlitchCube.config.redis_connection&.get('beacon:last_heartbeat')

      json({
             success: true,
             beacon_enabled: GlitchCube.config.beacon.enabled,
             beacon_url: GlitchCube.config.beacon.url&.gsub(%r{https?://([^/]+).*}, '\1'), # Show only domain
             last_heartbeat: last_heartbeat,
             device_id: GlitchCube.config.device.id,
             location: GlitchCube.config.device.location
           })
    end

    post '/api/v1/beacon/send' do
      content_type :json

      require_relative 'lib/services/beacon_service'
      beacon = Services::BeaconService.new

      success = beacon.send_heartbeat

      # Store timestamp in Redis
      GlitchCube.config.redis_connection.set('beacon:last_heartbeat', Time.now.iso8601) if success && GlitchCube.config.redis_connection

      json({
             success: success,
             timestamp: Time.now.iso8601
           })
    end

    post '/api/v1/beacon/alert' do
      content_type :json

      begin
        data = JSON.parse(request.body.read)

        require_relative 'lib/services/beacon_service'
        beacon = Services::BeaconService.new

        beacon.send_alert(data['message'], data['level'] || 'info')

        json({
               success: true,
               message: 'Alert sent'
             })
      rescue StandardError => e
        status 400
        json({
               success: false,
               error: e.message
             })
      end
    end
  end

  not_found do
    json({ error: 'Not found', status: 404 })
  end

  error do
    json({ error: 'Internal server error', status: 500 })
  end

  # Mock Home Assistant API endpoints (development only)
  if settings.mock_ha_enabled
    before '/mock_ha/api/*' do
      # Check mock authorization
      auth_header = request.env['HTTP_AUTHORIZATION']
      halt 401, json({ error: 'Unauthorized' }) if auth_header != 'Bearer mock-token-123'
    end

    # Mock HA state data
    def mock_ha_states
      @mock_ha_states ||= {
        'light.glitch_cube' => {
          entity_id: 'light.glitch_cube',
          state: 'on',
          attributes: {
            brightness: 255,
            rgb_color: [255, 128, 0],
            friendly_name: 'Glitch Cube Light'
          }
        },
        'sensor.battery_level' => {
          entity_id: 'sensor.battery_level',
          state: '85',
          attributes: {
            unit_of_measurement: '%',
            device_class: 'battery',
            friendly_name: 'Battery Level'
          }
        },
        'sensor.temperature' => {
          entity_id: 'sensor.temperature',
          state: '22.5',
          attributes: {
            unit_of_measurement: '°C',
            device_class: 'temperature',
            friendly_name: 'Temperature'
          }
        },
        'binary_sensor.motion' => {
          entity_id: 'binary_sensor.motion',
          state: 'off',
          attributes: {
            device_class: 'motion',
            friendly_name: 'Motion Detector'
          }
        },
        'camera.glitch_cube' => {
          entity_id: 'camera.glitch_cube',
          state: 'idle',
          attributes: {
            access_token: 'mock-camera-token',
            friendly_name: 'Glitch Cube Camera'
          }
        }
      }
    end

    # GET /mock_ha/api/states - Get all entity states
    get '/mock_ha/api/states' do
      content_type :json
      states = mock_ha_states.values.map do |state|
        state.merge(
          last_changed: Time.now.utc.iso8601,
          last_updated: Time.now.utc.iso8601
        )
      end
      json states
    end

    # GET /mock_ha/api/states/{entity_id} - Get specific entity state
    get '/mock_ha/api/states/:entity_id' do
      content_type :json
      entity = mock_ha_states[params[:entity_id]]
      if entity
        json entity.merge(
          last_changed: Time.now.utc.iso8601,
          last_updated: Time.now.utc.iso8601
        )
      else
        halt 404, json({ error: 'Entity not found' })
      end
    end

    # POST /mock_ha/api/states/{entity_id} - Update entity state
    post '/mock_ha/api/states/:entity_id' do
      content_type :json
      data = JSON.parse(request.body.read)

      # Update mock state
      mock_ha_states[params[:entity_id]] = {
        entity_id: params[:entity_id],
        state: data['state'],
        attributes: data['attributes'] || {}
      }

      json mock_ha_states[params[:entity_id]].merge(
        last_changed: Time.now.utc.iso8601,
        last_updated: Time.now.utc.iso8601
      )
    end

    # POST /mock_ha/api/services/{domain}/{service} - Call services
    post '/mock_ha/api/services/:domain/:service' do
      content_type :json
      data = begin
        JSON.parse(request.body.read)
      rescue StandardError
        {}
      end

      case "#{params[:domain]}/#{params[:service]}"
      when 'light/turn_on'
        entity_id = data['entity_id'] || 'light.glitch_cube'
        mock_ha_states[entity_id][:state] = 'on'
        mock_ha_states[entity_id][:attributes][:brightness] = data['brightness'] if data['brightness']
        mock_ha_states[entity_id][:attributes][:rgb_color] = data['rgb_color'] if data['rgb_color']

        json [{
          entity_id: entity_id,
          state: 'on',
          attributes: mock_ha_states[entity_id][:attributes],
          last_changed: Time.now.utc.iso8601,
          last_updated: Time.now.utc.iso8601
        }]

      when 'light/turn_off'
        entity_id = data['entity_id'] || 'light.glitch_cube'
        mock_ha_states[entity_id][:state] = 'off'
        mock_ha_states[entity_id][:attributes][:brightness] = 0

        json [{
          entity_id: entity_id,
          state: 'off',
          attributes: mock_ha_states[entity_id][:attributes],
          last_changed: Time.now.utc.iso8601,
          last_updated: Time.now.utc.iso8601
        }]

      when 'tts/google_translate_say', 'tts/speak'
        json({
               success: true,
               message: "Speaking: #{data['message']}",
               entity_id: data['entity_id'] || 'media_player.glitch_cube_speaker'
             })

      when 'conversation/process'
        json({
               response: {
                 speech: {
                   plain: {
                     speech: "I've processed your command: #{data['text']}"
                   }
                 }
               },
               conversation_id: "mock-conversation-#{Time.now.to_i}"
             })

      when 'camera/snapshot'
        json({
               filename: "/tmp/snapshot_#{Time.now.to_i}.jpg",
               entity_id: data['entity_id'] || 'camera.glitch_cube'
             })

      else
        halt 400, json({ error: 'Unknown service' })
      end
    end

    # Mock HA info endpoint
    get '/mock_ha/api/' do
      content_type :json
      json({
             message: 'Mock Home Assistant API (Development Mode)',
             version: '2024.1.0',
             base_url: "http://localhost:#{settings.port}/mock_ha"
           })
    end
  end
end

GlitchCubeApp.run! if __FILE__ == $PROGRAM_NAME
