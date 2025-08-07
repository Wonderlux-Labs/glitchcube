# frozen_string_literal: true

require_relative '../home_assistant_client'
require_relative '../services/logger_service'

# Tool for camera control and image capture
# Provides snapshot capture, motion detection, and visual analysis
class CameraTool
  def self.name
    'camera_control'
  end

  def self.description
    'Control cameras and capture visual input. Actions: "list_cameras" (verbose: true/false - shows available cameras), "take_snapshot" (camera, description), "get_motion_status" (shows motion detection state), "set_motion_sensitivity" (level), "analyze_scene" (camera, focus_area). Use for visual input, security monitoring, and scene analysis. Args: action (string), params (string) - JSON with camera, description, level, focus_area, etc.'
  end

  def self.call(action:, params: '{}')
    params = JSON.parse(params) if params.is_a?(String)

    client = HomeAssistantClient.new

    case action
    when 'list_cameras'
      list_available_cameras(client, params)
    when 'take_snapshot'
      take_camera_snapshot(client, params)
    when 'get_motion_status'
      get_motion_detection_status(client, params)
    when 'set_motion_sensitivity'
      set_motion_sensitivity(client, params)
    when 'analyze_scene'
      analyze_camera_scene(client, params)
    else
      "Unknown action: #{action}. Available actions: list_cameras, take_snapshot, get_motion_status, set_motion_sensitivity, analyze_scene"
    end
  rescue StandardError => e
    "Camera control error: #{e.message}"
  end

  # List all available cameras with their capabilities
  def self.list_available_cameras(client, params)
    verbose = params['verbose'] != false

    result = []
    result << '=== AVAILABLE CAMERAS ==='

    begin
      # Get all camera entities from Home Assistant
      states = client.states
      cameras = states.select { |state| state['entity_id'].start_with?('camera.') }

      if verbose
        cameras.each do |camera|
          entity_id = camera['entity_id']
          camera_name = entity_id.split('.').last

          if camera['state'] == 'unavailable'
            result << "  ❌ #{camera_name} (#{entity_id}): unavailable"
          else
            friendly_name = camera.dig('attributes', 'friendly_name')

            camera_info = "#{camera_name} (#{entity_id}): #{camera['state']}"
            camera_info += " - #{friendly_name}" if friendly_name && friendly_name != entity_id

            # Camera-specific attributes
            brand = camera.dig('attributes', 'brand')
            model = camera.dig('attributes', 'model')
            resolution = camera.dig('attributes', 'resolution')
            motion_detection = camera.dig('attributes', 'motion_detection')

            camera_info += " | #{brand} #{model}".strip if brand || model
            camera_info += " | Resolution: #{resolution}" if resolution
            camera_info += " | Motion: #{motion_detection}" if motion_detection

            result << "  ✅ #{camera_info}"
          end
        end

        # Motion detection entities
        motion_entities = states.select do |s|
          s['entity_id'].include?('motion') &&
            (s['entity_id'].start_with?('binary_sensor.') || s['entity_id'].start_with?('input_boolean.'))
        end

        if motion_entities.any?
          result << ''
          result << '🔍 MOTION DETECTION:'
          motion_entities.each do |entity|
            entity_name = entity['entity_id'].split('.').last
            friendly_name = entity.dig('attributes', 'friendly_name')
            status = entity['state'] == 'on' ? 'ACTIVE' : 'inactive'

            info = "  #{entity_name}: #{status}"
            info += " (#{friendly_name})" if friendly_name && friendly_name != entity_name
            result << info
          end
        end

        result << ''
        result << '=== USAGE EXAMPLES ==='
        result << 'Take snapshot: {"action": "take_snapshot", "params": {"camera": "tablet", "description": "visitor interaction"}}'
        result << 'Motion status: {"action": "get_motion_status", "params": {}}'
        result << 'Scene analysis: {"action": "analyze_scene", "params": {"camera": "tablet", "focus_area": "person detection"}}'

      else
        # Simple list
        available_cameras = []
        cameras.each do |camera|
          if camera['state'] != 'unavailable'
            camera_name = camera['entity_id'].split('.').last
            available_cameras << camera_name
          end
        end

        result << "Available: #{available_cameras.join(', ')}"
        result << 'Use verbose: true for detailed capabilities'
      end

      Services::LoggerService.log_api_call(
        service: 'camera_tool',
        endpoint: 'list_cameras',
        verbose: verbose,
        camera_count: cameras.size
      )

      result.join("\n")
    rescue StandardError => e
      "Error listing cameras: #{e.message}"
    end
  end

  # Take a snapshot from specified camera
  def self.take_camera_snapshot(client, params)
    camera = params['camera']
    description = params['description'] || 'manual snapshot'

    return 'Error: camera required' unless camera

    entity_id = resolve_camera_entity(client, camera)
    return "Error: Camera '#{camera}' not found" unless entity_id

    begin
      # Take snapshot using Home Assistant camera service
      client.call_service('camera', 'snapshot', {
                            entity_id: entity_id,
                            filename: "/config/www/snapshots/#{camera}_#{Time.now.to_i}.jpg"
                          })

      # Also try the direct snapshot method from HomeAssistantClient
      client.take_snapshot(entity_id: entity_id)

      Services::LoggerService.log_api_call(
        service: 'camera_tool',
        endpoint: 'take_snapshot',
        entity_id: entity_id,
        description: description
      )

      "📸 Captured snapshot from #{camera} - #{description}"
    rescue StandardError => e
      "Failed to capture snapshot from #{camera}: #{e.message}"
    end
  end

  # Get current motion detection status
  def self.get_motion_detection_status(client, _params)
    result = []
    result << '=== MOTION DETECTION STATUS ==='

    begin
      states = client.states

      # Check main motion boolean
      motion_boolean = states.find { |s| s['entity_id'] == 'input_boolean.motion_detected' }
      if motion_boolean
        status = motion_boolean['state'] == 'on' ? '🔴 MOTION DETECTED' : '🟢 No motion'
        result << "Main trigger: #{status}"

        last_changed = motion_boolean['last_changed']
        if last_changed
          time_ago = Time.now - Time.parse(last_changed)
          result << "Last changed: #{time_ago.round}s ago"
        end
      end

      # Check camera motion detection
      camera_motion = states.find { |s| s['entity_id'] == 'automation.camera_motion_vision_analysis' }
      if camera_motion
        status = camera_motion['state'] == 'on' ? 'enabled' : 'disabled'
        result << "Camera motion automation: #{status}"
      end

      # Check motion sensitivity setting
      sensitivity = states.find { |s| s['entity_id'] == 'select.camera_motion_detection_sensitivity' }
      result << "Motion sensitivity: #{sensitivity['state']}" if sensitivity

      # Check motion alarm
      alarm = states.find { |s| s['entity_id'] == 'switch.camera_motion_alarm' }
      if alarm
        status = alarm['state'] == 'on' ? 'enabled' : 'disabled'
        result << "Motion alarm: #{status}"
      end

      Services::LoggerService.log_api_call(
        service: 'camera_tool',
        endpoint: 'get_motion_status'
      )
    rescue StandardError => e
      result << "Error getting motion status: #{e.message}"
    end

    result.join("\n")
  end

  # Set motion detection sensitivity
  def self.set_motion_sensitivity(client, params)
    level = params['level']
    return 'Error: level required (low, medium, high)' unless level

    valid_levels = %w[low medium high]
    return "Error: level must be one of: #{valid_levels.join(', ')}" unless valid_levels.include?(level.to_s)

    begin
      # Set motion detection sensitivity via Home Assistant select entity
      client.call_service('select', 'select_option', {
                            entity_id: 'select.camera_motion_detection_sensitivity',
                            option: level.to_s
                          })

      Services::LoggerService.log_api_call(
        service: 'camera_tool',
        endpoint: 'set_motion_sensitivity',
        level: level
      )

      "Set motion detection sensitivity to #{level}"
    rescue StandardError => e
      "Failed to set motion sensitivity: #{e.message}"
    end
  end

  # Analyze current camera scene (placeholder for future AI vision integration)
  def self.analyze_camera_scene(client, params)
    camera = params['camera']
    focus_area = params['focus_area'] || 'general scene'

    return 'Error: camera required' unless camera

    entity_id = resolve_camera_entity(client, camera)
    return "Error: Camera '#{camera}' not found" unless entity_id

    begin
      # For now, this captures a snapshot and provides basic analysis
      # In the future, this would integrate with AI vision services

      # Take a snapshot first
      client.take_snapshot(entity_id: entity_id)

      # Get current camera state for basic info
      state = client.state(entity_id)

      result = []
      result << "=== SCENE ANALYSIS: #{camera.upcase} ==="
      result << "Focus area: #{focus_area}"
      result << ''

      if state && state['state'] != 'unavailable'
        # Basic scene information from camera attributes
        brand = state.dig('attributes', 'brand')
        model = state.dig('attributes', 'model')

        result << "📹 Camera: #{brand} #{model}".strip
        result << "📊 Status: #{state['state']}"

        # Mock analysis based on current motion detection
        motion_state = client.state('input_boolean.motion_detected')
        if motion_state && motion_state['state'] == 'on'
          result << '👤 Motion detected - possible human presence'
          result << '🎯 Recommended action: Engage in conversation'
        else
          result << '🏛️  Scene appears static'
          result << '💡 Consider proactive engagement if appropriate'
        end

        result << ''
        result << '📸 Snapshot captured for detailed analysis'
        result << '🔮 Note: Full AI vision analysis coming in future updates'

      else
        result << '❌ Camera unavailable - cannot analyze scene'
      end

      Services::LoggerService.log_api_call(
        service: 'camera_tool',
        endpoint: 'analyze_scene',
        entity_id: entity_id,
        focus_area: focus_area
      )

      result.join("\n")
    rescue StandardError => e
      "Failed to analyze scene from #{camera}: #{e.message}"
    end
  end

  # Resolve camera name to full entity ID
  def self.resolve_camera_entity(client, camera_name)
    return camera_name if camera_name.start_with?('camera.')

    # Try to find the entity by name
    states = client.states
    cameras = states.select { |state| state['entity_id'].start_with?('camera.') }

    # Look for exact match first
    exact_match = cameras.find do |c|
      c['entity_id'] == "camera.#{camera_name}" ||
        c.dig('attributes', 'friendly_name')&.downcase == camera_name.downcase
    end

    return exact_match['entity_id'] if exact_match

    # Look for partial match
    partial_match = cameras.find do |c|
      c['entity_id'].include?(camera_name) ||
        c.dig('attributes', 'friendly_name')&.downcase&.include?(camera_name.downcase)
    end

    partial_match&.dig('entity_id')
  rescue StandardError
    nil
  end
end
