# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require 'timeout'
require_relative 'services/circuit_breaker_service'
require_relative 'services/logger_service'
require_relative 'helpers/log_helper'
require_relative 'modules/error_handling'

class HomeAssistantClient
  include ErrorHandling

  class Error < StandardError; end
  class AuthenticationError < Error; end
  class NotFoundError < Error; end
  class TimeoutError < Error; end

  # Map voice names to ElevenLabs voice IDs
  ELEVENLABS_VOICE_MAP = {
    'Josh' => 'TxGEqnHWrfWFTfGW9XjX',
    'josh' => 'TxGEqnHWrfWFTfGW9XjX',
    'Luke' => 'pFZP5JQG7iQjIQuC4Bku',
    'luke' => 'pFZP5JQG7iQjIQuC4Bku',
    'Rachel' => '21m00Tcm4TlvDq8ikWAM',
    'rachel' => '21m00Tcm4TlvDq8ikWAM',
    'Bella' => 'EXAVITQu4vr4xnSDxMaL',
    'bella' => 'EXAVITQu4vr4xnSDxMaL',
    'Arnold' => 'VR6AewLTigWG4xSOukaG',
    'arnold' => 'VR6AewLTigWG4xSOukaG',
    'Adam' => 'pNInz6obpgDQGcFmaJgB',
    'adam' => 'pNInz6obpgDQGcFmaJgB',
    'Daniel' => 'onwK4e9ZLuTAKqWW03F9',
    'daniel' => 'onwK4e9ZLuTAKqWW03F9',
    'Sam' => 'yoZ06aMxZJJ28mfd3POQ',
    'sam' => 'yoZ06aMxZJJ28mfd3POQ',
    'Antoni' => 'ErXwobaYiN019PkySvjV',
    'antoni' => 'ErXwobaYiN019PkySvjV'
  }.freeze

  attr_reader :base_url, :token

  def initialize(base_url: nil, token: nil)
    # Always use the configured URL and token
    @base_url = base_url || GlitchCube.config.home_assistant.url
    @token = token || GlitchCube.config.home_assistant.token

    # In production, fail fast if not configured
    # In tests, VCR will handle the requests even with missing config
    return if GlitchCube.config.test?
    raise Error, 'Home Assistant URL not configured. Set HOME_ASSISTANT_URL or HA_URL environment variable.' unless @base_url
    raise Error, 'Home Assistant token not configured. Set HOME_ASSISTANT_TOKEN environment variable.' unless @token
  end

  # Get all entity states
  def states
    # Bypass circuit breaker in test environment unless explicitly testing circuit breakers
    return get('/api/states') if GlitchCube.config.test? && !ENV['ENABLE_CIRCUIT_BREAKERS']

    Services::CircuitBreakerService.home_assistant_breaker.call do
      get('/api/states')
    end
  rescue CircuitBreaker::CircuitOpenError => e
    puts "⚠️  Home Assistant circuit breaker is open: #{e.message}"
    # Return empty states when circuit is open
    []
  end

  # Get specific entity state
  def state(entity_id)
    # Bypass circuit breaker in test environment unless explicitly testing circuit breakers
    return get("/api/states/#{entity_id}") if GlitchCube.config.test? && !ENV['ENABLE_CIRCUIT_BREAKERS']

    Services::CircuitBreakerService.home_assistant_breaker.call do
      get("/api/states/#{entity_id}")
    end
  rescue CircuitBreaker::CircuitOpenError => e
    puts "⚠️  Home Assistant circuit breaker is open: #{e.message}"
    # Return default state when circuit is open
    { 'state' => 'unavailable', 'attributes' => {} }
  end

  # Update entity state
  def set_state(entity_id, state, attributes = {})
    post("/api/states/#{entity_id}", {
           state: state,
           attributes: attributes
         })
  end

  # Update a specific attribute of an entity
  def set_state_attribute(entity_id, attribute_name, attribute_value)
    # Get current state to preserve other attributes
    current = state(entity_id)
    current_attributes = current&.dig('attributes') || {}

    # Update the specific attribute
    updated_attributes = current_attributes.merge(attribute_name => attribute_value)

    # Set state with updated attributes
    set_state(entity_id, current&.dig('state') || 'unknown', updated_attributes)
  end

  # Call a service
  def call_service(domain, service, data = {}, return_response: false)
    # Add return_response query parameter if requested
    path = "/api/services/#{domain}/#{service}"
    path += '?return_response' if return_response

    # Bypass circuit breaker in test environment unless explicitly testing circuit breakers
    return post(path, data) if GlitchCube.config.test? && !ENV['ENABLE_CIRCUIT_BREAKERS']

    Services::CircuitBreakerService.home_assistant_breaker.call do
      post(path, data)
    end
  rescue CircuitBreaker::CircuitOpenError => e
    puts "⚠️  Home Assistant circuit breaker is open: #{e.message}"
    raise Error, 'Home Assistant temporarily unavailable'
  end

  # Light control methods
  def set_light(entity_id, brightness: nil, rgb_color: nil)
    data = { entity_id: entity_id }
    data[:brightness] = brightness if brightness
    data[:rgb_color] = rgb_color if rgb_color

    call_service('light', 'turn_on', data)
  end

  def turn_off_light(entity_id)
    call_service('light', 'turn_off', { entity_id: entity_id })
  end

  # TTS methods - Support multiple TTS providers via Home Assistant
  def speak(message, entity_id: nil, voice_options: {})
    target_entity = entity_id || 'media_player.square_voice'

    # Determine TTS provider from voice_options
    provider = voice_options[:tts] || :cloud

    begin
      LogHelper.log("🔊 TTS Request: '#{message}' to #{target_entity} via #{provider}")

      case provider
      when :elevenlabs
        speak_with_elevenlabs(message, target_entity, voice_options)
      else
        speak_with_cloud(message, target_entity, voice_options)
      end
    rescue Error => e
      LogHelper.error("Home Assistant TTS failed: #{e.message}")
      LogHelper.error("   Provider: #{provider}")
      LogHelper.error("   Entity: #{target_entity}")
      LogHelper.error("   Message: #{message}")
      LogHelper.error("   Error Class: #{e.class}")
      LogHelper.warning('Continuing without TTS')
      false
    rescue StandardError => e
      LogHelper.error("Unexpected TTS error: #{e.class} - #{e.message}")
      LogHelper.error("   Provider: #{provider}")
      LogHelper.error("   Entity: #{target_entity}")
      LogHelper.error("   Message: #{message}")
      LogHelper.error("   Backtrace: #{e.backtrace.first(3).join("\n   ")}")
      false
    end
  end

  private

  # Use Azure Cognitive Services TTS via tts.cloud_say
  def speak_with_cloud(message, target_entity, voice_options)
    # Check if queue mode is enabled (default to true if not set)
    use_queue = voice_options[:queue] != false

    if use_queue
      # Use the queued Cloud TTS script to prevent interruption
      script_params = {
        message: message,
        voice: voice_options[:voice] || 'JennyNeural',
        language: voice_options[:language] || 'en-US',
        media_player: target_entity
      }

      result = call_service('script', 'glitchcube_cloud_speak', script_params)
      LogHelper.success("Queued Cloud TTS: Voice=#{script_params[:voice]}, Response=#{result.inspect}")
    else
      # Direct TTS call (original behavior for testing or when queue is disabled)
      tts_params = {
        entity_id: target_entity,
        message: message,
        language: voice_options[:language] || 'en-US'
      }

      # Handle voice with optional style (e.g., "DavisNeural||excited")
      tts_params[:options] = { voice: voice_options[:voice] } if voice_options[:voice]

      result = call_service('tts', 'cloud_say', tts_params)
      LogHelper.success("Direct Cloud TTS: Response=#{result.inspect}")
    end

    true
  end

  # Use ElevenLabs TTS via tts.speak
  def speak_with_elevenlabs(message, target_entity, voice_options)
    # Get voice ID from name, or use as-is if already an ID
    voice_name = voice_options[:voice] || 'Josh'
    voice_id = ELEVENLABS_VOICE_MAP[voice_name] || voice_name

    # Check if queue mode is enabled (default to true if not set)
    use_queue = voice_options[:queue] != false

    if use_queue
      # Use the queued ElevenLabs TTS script to prevent interruption
      script_params = {
        message: message,
        voice: voice_id,
        media_player: target_entity,
        model: voice_options[:model] || 'eleven_multilingual_v2'
      }

      result = call_service('script', 'glitchcube_elevenlabs_speak', script_params)
      LogHelper.success("Queued ElevenLabs TTS: Voice=#{voice_id}, Response=#{result.inspect}")
    else
      # Direct TTS call (original behavior for testing or when queue is disabled)
      tts_params = {
        entity_id: 'tts.elevenlabs',
        media_player_entity_id: target_entity,
        message: message,
        options: {
          voice: voice_id, # Use the mapped voice ID
          model: voice_options[:model] || 'eleven_multilingual_v2'
        }
      }

      result = call_service('tts', 'speak', tts_params)
      LogHelper.success("Direct ElevenLabs TTS: Response=#{result.inspect}")
    end

    true
  end

  public

  # Voice assistant
  def process_voice_command(text)
    call_service('conversation', 'process', { text: text })
  end

  # Music Assistant search
  def search_music(query, limit: 5)
    call_service('music_assistant', 'search', {
                   name: query,
                   limit: limit
                 }, return_response: true)
  end

  # Camera
  def take_snapshot(entity_id: 'camera.glitch_cube')
    call_service('camera', 'snapshot', { entity_id: entity_id })
  end

  # AWTRIX Display Control Methods
  def awtrix_display_text(text, app_name: 'glitchcube', color: '#FFFFFF', duration: 5, rainbow: false, icon: nil)
    data = {
      app_name: app_name,
      text: text,
      color: color,
      duration: duration,
      rainbow: rainbow
    }
    data[:icon] = icon if icon

    with_error_handling('awtrix_display_text', fallback: false, reraise_unexpected: false) do
      call_service('script', 'awtrix_send_custom_app', data)
      true
    end
  end

  def awtrix_notify(text, color: '#FFFFFF', duration: 8, sound: nil, icon: nil, wakeup: true, stack: true)
    data = {
      text: text,
      color: color,
      duration: duration, # Using duration instead of hold since users can't dismiss
      wakeup: wakeup,
      stack: stack
    }
    data[:sound] = sound if sound
    data[:icon] = icon if icon

    with_error_handling('awtrix_notify', fallback: false, reraise_unexpected: false) do
      call_service('script', 'awtrix_send_notification', data)
      true
    end
  end

  def awtrix_clear_display
    with_error_handling('awtrix_clear_display', fallback: false, reraise_unexpected: false) do
      call_service('script', 'awtrix_clear_display', {})
      true
    end
  end

  def awtrix_mood_light(color, brightness: 100)
    with_error_handling('awtrix_mood_light', fallback: false, reraise_unexpected: false) do
      call_service('script', 'awtrix_set_mood_light', {
                     color: color,
                     brightness: brightness
                   })
      true
    end
  end

  # Sensor readings
  def battery_level
    state = state('sensor.battery_level')
    state['state'].to_i
  end

  def temperature
    state = state('sensor.temperature')
    state['state'].to_f
  end

  def motion_detected?
    state = state('binary_sensor.motion')
    state['state'] == 'on'
  end

  private

  def get(path)
    uri = URI.join(@base_url, path)
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{@token}"
    request['Content-Type'] = 'application/json'

    start_time = Time.now
    begin
      response = Net::HTTP.start(uri.hostname, uri.port,
                                 use_ssl: uri.scheme == 'https',
                                 open_timeout: 5,
                                 read_timeout: 10) do |http|
        http.request(request)
      end

      duration = ((Time.now - start_time) * 1000).round
      Services::LoggerService.log_api_call(
        service: 'home_assistant',
        endpoint: path,
        url: uri.to_s,
        method: 'GET',
        status: response.code.to_i,
        duration: duration
      )

      handle_response(response, request)
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
      duration = ((Time.now - start_time) * 1000).round
      Services::LoggerService.log_api_call(
        service: 'home_assistant',
        endpoint: path,
        url: uri.to_s,
        method: 'GET',
        duration: duration,
        error: "Timeout: #{e.message}"
      )
      raise TimeoutError, "Request timed out: #{e.message}"
    rescue SocketError, Errno::ECONNREFUSED => e
      duration = ((Time.now - start_time) * 1000).round
      Services::LoggerService.log_api_call(
        service: 'home_assistant',
        endpoint: path,
        url: uri.to_s,
        method: 'GET',
        duration: duration,
        error: "Connection failed: #{e.message}"
      )
      raise Error, "Connection failed: #{e.message}"
    end
  end

  def post(path, data)
    # Handle query parameters in path
    if path.include?('?')
      base_path, query_string = path.split('?', 2)
      uri = URI.join(@base_url, base_path)
      uri.query = query_string
    else
      uri = URI.join(@base_url, path)
    end

    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@token}"
    request['Content-Type'] = 'application/json'
    request.body = data.to_json

    start_time = Time.now
    begin
      response = Net::HTTP.start(uri.hostname, uri.port,
                                 use_ssl: uri.scheme == 'https',
                                 open_timeout: 5,
                                 read_timeout: 15) do |http| # Longer timeout for TTS requests
        http.request(request)
      end

      duration = ((Time.now - start_time) * 1000).round
      Services::LoggerService.log_api_call(
        service: 'home_assistant',
        endpoint: path,
        method: 'POST',
        status: response.code.to_i,
        duration: duration,
        request_data: data
      )

      handle_response(response, request)
    rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
      duration = ((Time.now - start_time) * 1000).round
      Services::LoggerService.log_api_call(
        service: 'home_assistant',
        endpoint: path,
        method: 'POST',
        duration: duration,
        error: "Timeout: #{e.message}"
      )
      raise TimeoutError, "Request timed out: #{e.message}"
    rescue SocketError, Errno::ECONNREFUSED => e
      duration = ((Time.now - start_time) * 1000).round
      Services::LoggerService.log_api_call(
        service: 'home_assistant',
        endpoint: path,
        method: 'POST',
        duration: duration,
        error: "Connection failed: #{e.message}"
      )
      raise Error, "Connection failed: #{e.message}"
    end
  end

  def handle_response(response, request = nil)
    case response.code.to_i
    when 200, 201
      JSON.parse(response.body)
    when 401
      raise AuthenticationError, 'Invalid token'
    when 404
      raise NotFoundError, 'Entity or service not found'
    when 400
      # Parse error details for better debugging
      error_body = begin
        JSON.parse(response.body)
      rescue StandardError
        response.body
      end

      # Extract meaningful error information
      error_details = []

      if error_body.is_a?(Hash)
        # Common Home Assistant error fields
        error_details << error_body['message'] if error_body['message']
        error_details << error_body['error'] if error_body['error']
        error_details << "Code: #{error_body['code']}" if error_body['code']

        # Service-specific errors
        error_details << "Error Code: #{error_body['error_code']}" if error_body['error_code']

        # Validation errors
        error_details << "Validation: #{error_body['errors']}" if error_body['errors']
      end

      # Fallback to raw response
      error_details << response.body if error_details.empty?

      # Enhanced logging for debugging
      if request
        puts '❌ Home Assistant 400 Error:'
        puts "  Endpoint: #{response.uri}"
        puts "  Method: #{request.method}"
        puts "  Headers: #{request.each_header.to_h}"
        puts "  Request Body: #{request.body}"
        puts "  Response Status: #{response.code}"
        puts "  Response Headers: #{response.each_header.to_h}"
        puts "  Response Body: #{response.body}"
        error_details.each { |detail| puts "  Error: #{detail}" }
      end

      # Create comprehensive error message
      error_summary = error_details.join(' | ')
      endpoint_info = request ? " (#{request.method} #{response.uri})" : ''

      raise Error, "Bad Request (400)#{endpoint_info}: #{error_summary}"
    when 500
      # Parse 500 error details for better debugging
      error_body = begin
        JSON.parse(response.body)
      rescue StandardError
        response.body
      end

      error_msg = if error_body.is_a?(Hash)
                    error_body['message'] || error_body['error'] || response.body
                  else
                    response.body
                  end

      # Log the full request for debugging 500 errors
      if request
        puts '❌ Home Assistant 500 Error Details:'
        puts "  Endpoint: #{response.uri}"
        puts "  Request Body: #{request.body}"
        puts "  Response Status: #{response.code}"
        puts "  Response Body: #{response.body}"
        puts "  Parsed Error: #{error_msg}"
      end

      raise Error, "Internal Server Error (500): #{error_msg}"
    else
      raise Error, "HA API error: #{response.code} - #{response.body}"
    end
  end
end
