# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'
require 'timeout'
require_relative 'services/circuit_breaker_service'
require_relative 'services/logger_service'

class HomeAssistantClient
  class Error < StandardError; end
  class AuthenticationError < Error; end
  class NotFoundError < Error; end
  class TimeoutError < Error; end

  attr_reader :base_url, :token

  def initialize(base_url: nil, token: nil)
    if GlitchCube.config.home_assistant.mock_enabled
      # Use mock HA endpoints when explicitly enabled
      @base_url = base_url || GlitchCube.config.home_assistant.url || "http://localhost:#{GlitchCube.config.port}/mock_ha"
      @token = token || GlitchCube.config.home_assistant.token || 'mock-token-123'
    else
      # Use real HA - fail if not configured
      @base_url = base_url || GlitchCube.config.home_assistant.url
      @token = token || GlitchCube.config.home_assistant.token

      raise Error, 'Home Assistant URL not configured. Set HOME_ASSISTANT_URL or HA_URL environment variable.' unless @base_url
      raise Error, 'Home Assistant token not configured. Set HOME_ASSISTANT_TOKEN environment variable.' unless @token
    end
  end

  # Get all entity states
  def states
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

  # Call a service
  def call_service(domain, service, data = {})
    Services::CircuitBreakerService.home_assistant_breaker.call do
      post("/api/services/#{domain}/#{service}", data)
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

  # TTS methods - Updated for new Home Assistant format
  def speak(message, entity_id: nil)
    target_entity = entity_id || 'media_player.square_voice'
    
    # Try new format first (tts.speak action with tts.home_assistant_cloud)
    begin
      # Use tts.home_assistant_cloud as the TTS engine
      # New HA format requires target and data to be separate
      post('/api/services/tts/speak', {
             target: {
               entity_id: 'tts.home_assistant_cloud'
             },
             data: {
               media_player_entity_id: target_entity,
               message: message
             }
           })
    rescue Error => e
      # Fallback to legacy cloud_say format
      begin
        call_service('tts', 'cloud_say', {
                       entity_id: target_entity,
                       message: message
                     })
      rescue Error => fallback_error
        # Final fallback to google_translate 
        begin
          call_service('tts', 'google_translate_say', {
                         entity_id: target_entity,
                         message: message
                       })
        rescue Error => final_error
          puts "⚠️  All TTS methods failed: #{e.message} | #{fallback_error.message} | #{final_error.message}"
          # Don't raise error - just log and continue without TTS
          puts "🔇 Continuing without TTS"
          return false
        end
      end
    end
    
    true
  end

  # Voice assistant
  def process_voice_command(text)
    call_service('conversation', 'process', { text: text })
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

    call_service('script', 'awtrix_send_custom_app', data)
  rescue Error => e
    puts "⚠️  Failed to send text to AWTRIX: #{e.message}"
    false
  end

  def awtrix_notify(text, color: '#FFFFFF', duration: 8, sound: nil, icon: nil, wakeup: true, stack: true)
    data = {
      text: text,
      color: color,
      duration: duration,  # Using duration instead of hold since users can't dismiss
      wakeup: wakeup,
      stack: stack
    }
    data[:sound] = sound if sound
    data[:icon] = icon if icon

    call_service('script', 'awtrix_send_notification', data)
  rescue Error => e
    puts "⚠️  Failed to send notification to AWTRIX: #{e.message}"
    false
  end

  def awtrix_clear_display
    call_service('script', 'awtrix_clear_display', {})
  rescue Error => e
    puts "⚠️  Failed to clear AWTRIX display: #{e.message}"
    false
  end

  def awtrix_mood_light(color, brightness: 100)
    call_service('script', 'awtrix_set_mood_light', {
                   color: color,
                   brightness: brightness
                 })
  rescue Error => e
    puts "⚠️  Failed to set AWTRIX mood light: #{e.message}"
    false
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

      handle_response(response)
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
    uri = URI.join(@base_url, path)
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

      handle_response(response)
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

  def handle_response(response)
    case response.code.to_i
    when 200, 201
      JSON.parse(response.body)
    when 401
      raise AuthenticationError, 'Invalid token'
    when 404
      raise NotFoundError, 'Entity or service not found'
    else
      raise Error, "HA API error: #{response.code} - #{response.body}"
    end
  end
end
