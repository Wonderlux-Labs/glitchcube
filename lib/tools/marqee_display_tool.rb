# frozen_string_literal: true

# Tool for controlling AWTRIX LED matrix display system
# Provides text display, notifications, mood lighting
class DisplayTool < BaseTool
  def self.name
    'display_control'
  end

  def self.description
    'Control AWTRIX 32x8 LED matrix display for scrolling text, notifications, and visual feedback. Primary display for Glitch Cube status and messages.'
  end

  def self.category
    'visual_interface'
  end

  def self.tool_prompt
    'Control 32x8 LED matrix with display_text(), send_notification(), set_mood_light(), clear_display().'
  end

  # List of available tool methods for this class
  def self.available_tools
    %w[display_text send_notification set_mood_light clear_display]
  end

  # Prompt description for LLM
  def self.prompt_description
    'Control AWTRIX LED matrix display for text and notifications'
  end

  # Tool schemas for each method
  def self.tool_schemas
    {
      'display_text' => {
        'type' => 'object',
        'properties' => {
          'text' => { 'type' => 'string' },
          'rainbow' => { 'type' => 'boolean' },
          'icon' => { 'type' => 'string' },
          'duration' => { 'type' => 'integer', 'minimum' => 1, 'maximum' => 60 }
        },
        'required' => ['text']
      },
      'send_notification' => {
        'type' => 'object',
        'properties' => {
          'message' => { 'type' => 'string' },
          'icon' => { 'type' => 'string' },
          'sound' => { 'type' => 'string', 'enum' => %w[beep alarm notification] }
        },
        'required' => ['message']
      },
      'set_mood_light' => {
        'type' => 'object',
        'properties' => {
          'rgb' => { 'type' => 'array', 'items' => { 'type' => 'integer', 'minimum' => 0, 'maximum' => 255 } },
          'brightness' => { 'type' => 'integer', 'minimum' => 0, 'maximum' => 100 }
        },
        'required' => %w[rgb brightness]
      },
      'clear_display' => { 'type' => 'object', 'properties' => {} }
    }
  end

  # AWTRIX device entity ID
  AWTRIX_DEVICE = 'awtrix_bedroom'
  AWTRIX_MATRIX_LIGHT = 'light.awtrix_b85e20_matrix'

  # Display text on AWTRIX as a custom app
  def self.display_text(text:, rainbow: false, icon: nil, duration: 5, **_kwargs)
    service_data = {
      name: 'glitchcube',
      data: {
        text: text,
        rainbow: rainbow,
        duration: duration,
        lifetime: 900, # 15 minutes
        pushIcon: 0
      }
    }

    service_data[:data][:icon] = icon if icon

    result = call_ha_service('awtrix', "#{AWTRIX_DEVICE}_push_app_data", service_data)

    Services::LoggerService.log_api_call(
      service: 'display_tool',
      endpoint: 'display_text',
      text: text,
      success: result.include?('✅')
    )

    if result.include?('✅')
      "Displayed: '#{text}' #{'with rainbow' if rainbow} for #{duration}s"
    else
      result
    end
  rescue StandardError => e
    "Failed to display text: #{e.message}"
  end

  # Send notification to AWTRIX
  def self.send_notification(message:, icon: nil, sound: nil, **_kwargs)
    service_data = {
      message: message
    }

    # Add optional data if provided
    if icon || sound
      service_data[:data] = {}
      service_data[:data][:icon] = icon if icon
      service_data[:data][:sound] = sound if sound
    end

    result = call_ha_service('notify', AWTRIX_DEVICE, service_data)

    Services::LoggerService.log_api_call(
      service: 'display_tool',
      endpoint: 'send_notification',
      message: message,
      success: result.include?('✅')
    )

    if result.include?('✅')
      sound_desc = sound ? " with #{sound} sound" : ''
      "Sent notification: '#{message}'#{sound_desc}"
    else
      result
    end
  rescue StandardError => e
    "Failed to send notification: #{e.message}"
  end

  # Set mood light on AWTRIX matrix
  def self.set_mood_light(rgb:, brightness:)
    # Validate RGB array
    return 'RGB must be array of 3 values [R,G,B]' unless rgb.is_a?(Array) && rgb.length == 3

    # Convert brightness from 0-100 to 0-255
    brightness_twotwofive = (brightness * 2.55).round

    service_data = {
      entity_id: AWTRIX_MATRIX_LIGHT,
      rgb_color: rgb,
      brightness: brightness_twotwofive
    }

    result = call_ha_service('light', 'turn_on', service_data)

    Services::LoggerService.log_api_call(
      service: 'display_tool',
      endpoint: 'set_mood_light',
      rgb: rgb,
      brightness: brightness,
      success: result.include?('✅')
    )

    if result.include?('✅')
      "Set mood light to RGB(#{rgb.join(',')}) at #{brightness}% brightness"
    else
      result
    end
  rescue StandardError => e
    "Failed to set mood light: #{e.message}"
  end

  # Clear the display (remove custom app)
  def self.clear_display
    # Remove the glitchcube app
    service_data = {
      name: 'glitchcube'
    }

    result = call_ha_service('awtrix', "#{AWTRIX_DEVICE}_push_app_data", service_data)

    Services::LoggerService.log_api_call(
      service: 'display_tool',
      endpoint: 'clear_display',
      success: result.include?('✅')
    )

    if result.include?('✅')
      'Display cleared'
    else
      result
    end
  rescue StandardError => e
    "Failed to clear display: #{e.message}"
  end

  # Icon reference for common icons
  ICONS = {
    'warning' => '33655',
    'info' => '87',
    'success' => '1542',
    'error' => '4276',
    'heart' => '8319',
    'music' => '31209',
    'home' => '2472',
    'temperature' => '3734',
    'humidity' => '51764',
    'light' => '2342'
  }.freeze

  # Sound options
  SOUNDS = %w[beep alarm notification].freeze
end
