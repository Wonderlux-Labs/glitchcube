# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

class HomeAssistantClient
  class Error < StandardError; end
  class AuthenticationError < Error; end
  class NotFoundError < Error; end

  attr_reader :base_url, :token

  def initialize(base_url: nil, token: nil)
    if GlitchCube.config.home_assistant.mock_enabled
      # Use mock HA endpoints when explicitly enabled
      @base_url = base_url || GlitchCube.config.home_assistant.url || "http://localhost:#{GlitchCube.config.port}/mock_ha"
      @token = token || GlitchCube.config.home_assistant.token || 'mock-token-123'
    else
      # Use real HA by default
      @base_url = base_url || GlitchCube.config.home_assistant.url || 'http://localhost:8123'
      @token = token || GlitchCube.config.home_assistant.token
    end
  end

  # Get all entity states
  def states
    get('/api/states')
  end

  # Get specific entity state
  def state(entity_id)
    get("/api/states/#{entity_id}")
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
    post("/api/services/#{domain}/#{service}", data)
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

  # TTS methods
  def speak(message, entity_id: nil)
    call_service('tts', 'speak', {
                   message: message,
                   entity_id: entity_id || 'media_player.glitch_cube_speaker'
                 })
  end

  # Voice assistant
  def process_voice_command(text)
    call_service('conversation', 'process', { text: text })
  end

  # Camera
  def take_snapshot(entity_id: 'camera.glitch_cube')
    call_service('camera', 'snapshot', { entity_id: entity_id })
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

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(request)
    end

    handle_response(response)
  end

  def post(path, data)
    uri = URI.join(@base_url, path)
    request = Net::HTTP::Post.new(uri)
    request['Authorization'] = "Bearer #{@token}"
    request['Content-Type'] = 'application/json'
    request.body = data.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(request)
    end

    handle_response(response)
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
