# frozen_string_literal: true

require_relative 'base_tool'
require_relative '../services/logger_service'

# Tool for controlling AWTRIX LED matrix display system
# Provides text display, notifications, mood lighting, and visual effects
class DisplayTool < BaseTool
  def self.name
    'display_control'
  end

  def self.description
    'Control AWTRIX 32x8 LED matrix display and status indicators. Supports text display, notifications, mood lighting, and status queries.'
  end

  def self.category
    'visual_interface'
  end

  def self.tool_prompt
    "Control 32x8 LED matrix with display_text(), send_notification(), set_mood_light(), clear_display()."
  end

  # AWTRIX entities based on our hardware scan
  DISPLAY_ENTITIES = {
    'matrix' => 'light.awtrix_b85e20_matrix', # Main 32x8 RGB LED matrix
    'indicator_1' => 'light.awtrix_b85e20_indicator_1', # Status indicator 1
    'indicator_2' => 'light.awtrix_b85e20_indicator_2', # Status indicator 2
    'indicator_3' => 'light.awtrix_b85e20_indicator_3'  # Status indicator 3
  }.freeze

  # List all available display entities and their capabilities
  def self.list_available_displays(verbose: true)

    result = []
    result << '=== AVAILABLE DISPLAYS ==='

    if verbose
      DISPLAY_ENTITIES.each do |key, entity_id|
        state = ha_client.state(entity_id)

        if state && state['state'] != 'unavailable'
          supported_modes = state.dig('attributes', 'supported_color_modes') || []
          current_brightness = state.dig('attributes', 'brightness')
          current_rgb = state.dig('attributes', 'rgb_color')
          friendly_name = state.dig('attributes', 'friendly_name')

          display_info = "#{key} (#{entity_id}): #{state['state']}"
          display_info += " - #{friendly_name}" if friendly_name && friendly_name != entity_id

          if key == 'matrix'
            display_info += ' | 32x8 RGB matrix'
            display_info += ' | Text display, notifications, mood lighting'
          else
            display_info += ' | Status indicator'
          end

          display_info += " | Modes: #{supported_modes.join(', ')}" if supported_modes.any?
          display_info += " | Brightness: #{current_brightness}" if current_brightness
          display_info += " | Color: #{current_rgb}" if current_rgb

          result << "  ✅ #{display_info}"
        else
          result << "  ❌ #{key} (#{entity_id}): unavailable"
        end
      rescue StandardError => e
        result << "  ❌ #{key} (#{entity_id}): error - #{e.message}"
      end

      # Show AWTRIX capabilities
      result << ''
      result << '=== AWTRIX CAPABILITIES ==='
      result << '  📝 Text Display: Custom apps with colors, icons, rainbow effects'
      result << '  🔔 Notifications: Alerts with sounds, icons, auto-dismiss timers'
      result << '  💡 Mood Lighting: Background lighting effects'
      result << '  🎵 Sound Effects: RTTTL ringtones or MP3 files'
      result << '  🎨 Icons: Numeric IDs (1-9999) or base64 8x8 pixel art'

      # Usage examples
      result << ''
      result << '=== USAGE EXAMPLES ==='
      result << 'Show text: {"action": "show_text", "params": {"text": "Hello!", "color": "#00FF00", "duration": 10}}'
      result << 'Notification: {"action": "notify", "params": {"text": "Alert!", "color": "#FF0000", "sound": "alarm"}}'
      result << 'Mood light: {"action": "mood_light", "params": {"color": "#FF00FF", "brightness": 150}}'

    else
      # Simple list
      available_displays = []
      display_entities.each do |key, entity_id|
        state = ha_client.state(entity_id)
        available_displays << key if state && state['state'] != 'unavailable'
      rescue StandardError
        # Skip errors in simple mode
      end

      result << "Available: #{available_displays.join(', ')}"
      result << 'Matrix: 32x8 RGB display for text/notifications'
      result << 'Indicators: 3x RGB status lights'
      result << 'Use verbose: true for detailed capabilities'
    end

    Services::LoggerService.log_api_call(
      service: 'display_tool',
      endpoint: 'list_displays',
      verbose: verbose,
      available_count: display_entities.size
    )

    result.join("\n")
  rescue StandardError => e
    "Error listing displays: #{e.message}"
  end

  # Display text on the AWTRIX matrix
  def self.show_display_text(text:, app_name: 'glitchcube', color: '#FFFFFF', duration: 5, rainbow: false, icon: nil)
    return format_response(false, 'Text is required') if text.nil? || text.empty?

    # Build display parameters
    display_params = {
      app_name: app_name,
      text: text,
      color: color,
      duration: duration,
      rainbow: rainbow
    }

    # Add icon if provided
    display_params[:icon] = icon if icon

    begin
      # Use existing AWTRIX method from HomeAssistantClient
      success = ha_client.awtrix_display_text(
        text,
        app_name: display_params[:app_name],
        color: display_params[:color],
        duration: display_params[:duration],
        rainbow: display_params[:rainbow],
        icon: display_params[:icon]
      )

      Services::LoggerService.log_api_call(
        service: 'display_tool',
        endpoint: 'show_text',
        text: text,
        color: display_params[:color],
        duration: display_params[:duration]
      )

      if success
        duration_desc = "for #{display_params[:duration]}s"
        color_desc = display_params[:color]
        rainbow_desc = display_params[:rainbow] ? ' (rainbow effect)' : ''
        icon_desc = display_params[:icon] ? " with icon #{display_params[:icon]}" : ''

        "Displayed '#{text}' in #{color_desc}#{rainbow_desc} #{duration_desc}#{icon_desc}"
      else
        'Failed to display text on matrix'
      end
    rescue StandardError => e
      "Failed to show display text: #{e.message}"
    end
  end

  # Send notification to AWTRIX
  def self.send_notification(params)
    text = params['text']
    return 'Error: text required' unless text

    # Build notification parameters
    notify_params = {
      color: params['color'] || '#FFFFFF',
      duration: params['duration'] || 8,
      wakeup: params['wakeup'] != false,  # Default true
      stack: params['stack'] != false     # Default true
    }

    # Add optional parameters
    notify_params[:sound] = params['sound'] if params['sound']
    notify_params[:icon] = params['icon'] if params['icon']

    begin
      success = ha_client.awtrix_notify(
        text,
        color: notify_params[:color],
        duration: notify_params[:duration],
        sound: notify_params[:sound],
        icon: notify_params[:icon],
        wakeup: notify_params[:wakeup],
        stack: notify_params[:stack]
      )

      Services::LoggerService.log_api_call(
        service: 'display_tool',
        endpoint: 'notify',
        text: text,
        color: notify_params[:color],
        sound: notify_params[:sound]
      )

      if success
        sound_desc = notify_params[:sound] ? " with sound '#{notify_params[:sound]}'" : ''
        icon_desc = notify_params[:icon] ? " and icon #{notify_params[:icon]}" : ''

        "Sent notification: '#{text}'#{sound_desc}#{icon_desc}"
      else
        'Failed to send notification'
      end
    rescue StandardError => e
      "Failed to send notification: #{e.message}"
    end
  end

  # Set AWTRIX mood lighting
  def self.set_mood_light(params)
    color = params['color']
    return 'Error: color required' unless color

    brightness = params['brightness'] || 100

    # Validate color format
    return 'Error: color must be hex format like #FF0000' unless color.match?(/^#[0-9A-Fa-f]{6}$/)

    begin
      success = ha_client.awtrix_mood_light(color, brightness: brightness)

      Services::LoggerService.log_api_call(
        service: 'display_tool',
        endpoint: 'mood_light',
        color: color,
        brightness: brightness
      )

      if success
        "Set AWTRIX mood light to #{color} at #{brightness} brightness"
      else
        'Failed to set mood lighting'
      end
    rescue StandardError => e
      "Failed to set mood lighting: #{e.message}"
    end
  end

  # Clear all custom apps from display
  def self.clear_display()
    success = ha_client.awtrix_clear_display

    Services::LoggerService.log_api_call(
      service: 'display_tool',
      endpoint: 'clear_display'
    )

    if success
      'Cleared AWTRIX display'
    else
      'Failed to clear display'
    end
  rescue StandardError => e
    "Failed to clear display: #{e.message}"
  end

  # Get status of display entities
  def self.get_display_status(display_entities)
    statuses = []

    display_entities.each do |key, entity_id|
      state = ha_client.state(entity_id)

      if state && state['state'] != 'unavailable'
        status = "#{key}: #{state['state']}"

        if state['state'] == 'on'
          brightness = state.dig('attributes', 'brightness')
          rgb_color = state.dig('attributes', 'rgb_color')

          status += ", brightness #{brightness}" if brightness
          status += ", rgb #{rgb_color}" if rgb_color
        end

        statuses << status
      else
        statuses << "#{key}: unavailable"
      end
    rescue StandardError => e
      statuses << "#{key}: error - #{e.message}"
    end

    # Also try to get any active AWTRIX apps (this would require additional HA integration)
    statuses.join(' | ')
  end
end
