# frozen_string_literal: true

require_relative 'base_tool'
require_relative '../services/logger_service'

# Tool for camera control and image capture
# Provides snapshot capture, motion detection, and visual analysis
class CameraTool < BaseTool
  def self.name
    'camera_control'
  end

  def self.description
    'Control cameras and capture visual input for the Glitch Cube art installation. Provides camera listing, snapshot capture, motion detection monitoring, and scene analysis.'
  end

  def self.category
    'visual_interface'
  end

  def self.tool_prompt
    'Capture images and analyze scenes with take_snapshot(), check_motion(), analyze_scene().'
  end

  # List all available cameras with their capabilities
  def self.list_cameras(verbose: true)
    result = []
    result << '=== AVAILABLE CAMERAS ==='

    begin
      # Get all camera entities from Home Assistant
      states = ha_client.states
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
        result << 'Use take_snapshot method with camera name and description'
        result << 'Use get_motion_status to check current motion detection'
        result << 'Use analyze_scene with camera name and focus area'

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

      format_response(true, result.join("\n"))
    rescue StandardError => e
      format_response(false, "Error listing cameras: #{e.message}")
    end
  end

  # Take a snapshot from specified camera
  def self.take_snapshot(camera:, description: 'manual snapshot')
    return format_response(false, 'Camera name is required') if camera.nil? || camera.empty?

    entity_id = resolve_camera_entity(camera)
    return format_response(false, "Camera '#{camera}' not found") unless entity_id

    begin
      # Take snapshot using Home Assistant camera service
      call_ha_service('camera', 'snapshot', {
                        entity_id: entity_id,
                        filename: "/config/www/snapshots/#{camera}_#{Time.now.to_i}.jpg"
                      })

      # Also try the direct snapshot method from HomeAssistantClient
      ha_client.take_snapshot(entity_id: entity_id)

      Services::LoggerService.log_api_call(
        service: 'camera_tool',
        endpoint: 'take_snapshot',
        entity_id: entity_id,
        description: description
      )

      format_response(true, "📸 Captured snapshot from #{camera} - #{description}")
    rescue StandardError => e
      format_response(false, "Failed to capture snapshot from #{camera}: #{e.message}")
    end
  end

  # Get current motion detection status
  def self.get_motion_status
    result = []
    result << '=== MOTION DETECTION STATUS ==='

    begin
      states = ha_client.states

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

      format_response(true, result.join("\n"))
    rescue StandardError => e
      format_response(false, "Error getting motion status: #{e.message}")
    end
  end

  # Set motion detection sensitivity
  def self.set_motion_sensitivity(level:)
    return format_response(false, 'Level is required (low, medium, high)') if level.nil? || level.empty?

    valid_levels = %w[low medium high]
    return format_response(false, "Level must be one of: #{valid_levels.join(', ')}") unless valid_levels.include?(level.to_s)

    begin
      # Set motion detection sensitivity via Home Assistant select entity
      call_ha_service('select', 'select_option', {
                        entity_id: 'select.camera_motion_detection_sensitivity',
                        option: level.to_s
                      })

      Services::LoggerService.log_api_call(
        service: 'camera_tool',
        endpoint: 'set_motion_sensitivity',
        level: level
      )

      format_response(true, "Set motion detection sensitivity to #{level}")
    rescue StandardError => e
      format_response(false, "Failed to set motion sensitivity: #{e.message}")
    end
  end

  # Analyze current camera scene (placeholder for future AI vision integration)
  def self.analyze_scene(camera:, focus_area: 'general scene')
    return format_response(false, 'Camera name is required') if camera.nil? || camera.empty?

    entity_id = resolve_camera_entity(camera)
    return format_response(false, "Camera '#{camera}' not found") unless entity_id

    begin
      # For now, this captures a snapshot and provides basic analysis
      # In the future, this would integrate with AI vision services

      # Take a snapshot first
      ha_client.take_snapshot(entity_id: entity_id)

      # Get current camera state for basic info
      state = ha_client.state(entity_id)

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
        motion_state = ha_client.state('input_boolean.motion_detected')
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

      format_response(true, result.join("\n"))
    rescue StandardError => e
      format_response(false, "Failed to analyze scene from #{camera}: #{e.message}")
    end
  end

  # Resolve camera name to full entity ID
  def self.resolve_camera_entity(camera_name)
    return camera_name if camera_name.start_with?('camera.')

    # Try to find the entity by name
    states = ha_client.states
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
