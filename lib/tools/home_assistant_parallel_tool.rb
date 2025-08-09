# frozen_string_literal: true

require 'concurrent'
require 'json'
require_relative 'base_tool'

# Enhanced Home Assistant tool with parallel execution support
class HomeAssistantParallelTool < BaseTool
  def self.name
    'home_assistant_parallel'
  end

  def self.description
    'Execute multiple Home Assistant actions in parallel for faster response. ' \
      'Supports batch operations like setting multiple lights, getting all sensors, ' \
      'and executing complex sequences. Args: actions (array of {action: string, params: object})'
  end

  def self.parameters
    {
      'actions' => {
        type: 'array',
        description: 'Array of actions to execute in parallel',
        items: {
          type: 'object',
          properties: {
            'action' => { type: 'string' },
            'params' => { type: 'object' }
          }
        }
      }
    }
  end

  def self.required_parameters
    %w[actions]
  end

  def self.category
    'system_integration'
  end

  def self.call(actions:)
    # Parse actions if it's a JSON string
    actions = JSON.parse(actions) if actions.is_a?(String)

    # Ensure actions is an array
    actions = [actions] unless actions.is_a?(Array)

    # Add resource limit as mentioned in PR review
    return format_response(false, "Too many parallel actions (#{actions.length}). Maximum allowed: 5") if actions.length > 5

    # Execute all actions in parallel
    results = Concurrent::Array.new
    futures = actions.map do |action_spec|
      Concurrent::Future.execute do
        execute_single_action(action_spec)
      end
    end

    # Wait for all futures to complete (with timeout)
    futures.each_with_index do |future, index|
      result = future.value(3) # 3 second timeout per action
      results[index] = if result.nil?
                         # Timeout occurred - future.value returns nil on timeout
                         { error: "Action #{index} timed out", action: actions[index] }
                       else
                         result
                       end
    rescue StandardError => e
      results[index] = { error: e.message, action: actions[index] }
    end

    format_parallel_results(results)
  rescue StandardError => e
    "Error executing parallel actions: #{e.message}"
  end

  def self.execute_single_action(action_spec)
    action = action_spec['action'] || action_spec[:action]
    params = action_spec['params'] || action_spec[:params] || {}

    case action
    when 'get_sensor'
      get_sensor_value(params)
    when 'set_light'
      set_light_state(params)
    when 'speak'
      speak_message(params)
    when 'awtrix_display'
      display_on_awtrix(params)
    when 'run_script'
      run_ha_script(params)
    when 'call_service'
      call_ha_service_action(params)
    else
      { error: "Unknown action: #{action}" }
    end
  rescue StandardError => e
    { error: "Action '#{action}' failed: #{e.message}" }
  end

  def self.get_sensor_value(params)
    entity_id = params['entity_id']
    return { error: 'entity_id required for get_sensor' } unless entity_id

    # Access ha_client directly since we inherit from BaseTool
    client = ha_client
    state = client.state(entity_id)

    if state
      {
        entity_id: entity_id,
        value: state['state'],
        unit: state.dig('attributes', 'unit_of_measurement'),
        friendly_name: state.dig('attributes', 'friendly_name')
      }
    else
      { error: "Failed to get state for #{entity_id}" }
    end
  end

  def self.set_light_state(params)
    entity_id = params['entity_id'] || 'light.glitch_cube'
    client = ha_client

    if params['state'] == 'off'
      success = if client.respond_to?(:turn_off_light)
                  client.turn_off_light(entity_id)
                  true
                else
                  result = call_ha_service('light', 'turn_off', { entity_id: entity_id })
                  result.include?('✅')
                end
      { entity_id: entity_id, state: 'off', success: success }
    else
      brightness = params['brightness']
      rgb_color = params['rgb_color']

      success = if client.respond_to?(:set_light)
                  client.set_light(entity_id, brightness: brightness, rgb_color: rgb_color)
                  true
                else
                  service_data = { entity_id: entity_id }
                  service_data[:brightness] = brightness if brightness
                  service_data[:rgb_color] = rgb_color if rgb_color
                  result = call_ha_service('light', 'turn_on', service_data)
                  result.include?('✅')
                end

      { entity_id: entity_id, state: 'on', brightness: brightness, rgb_color: rgb_color, success: success }
    end
  end

  def self.speak_message(params)
    message = params['message']
    return { error: 'message required for speak' } unless message

    entity_id = params['entity_id'] || 'media_player.square_voice'

    # Use ha_client directly
    client = ha_client
    success = if client.respond_to?(:speak)
                client.speak(message, entity_id: entity_id)
              else
                result = call_ha_service('tts', 'speak', {
                                           entity_id: entity_id,
                                           message: message
                                         })
                result.include?('✅')
              end

    { action: 'speak', message: message, success: success }
  end

  def self.display_on_awtrix(params)
    text = params['text']
    return { error: 'text required for AWTRIX display' } unless text

    color = params['color'] || [255, 255, 255]
    duration = params['duration'] || 5
    rainbow = params['rainbow'] || false

    # Use ha_client directly
    client = ha_client
    success = if client.respond_to?(:awtrix_display_text)
                client.awtrix_display_text(text, color: color, duration: duration, rainbow: rainbow)
              else
                # Fallback to service call
                result = call_ha_service('awtrix', 'display_text', {
                                           text: text,
                                           color: color,
                                           duration: duration,
                                           rainbow: rainbow
                                         })
                result.include?('✅')
              end

    { action: 'awtrix_display', text: text, success: success }
  end

  def self.run_ha_script(params)
    script_name = params['script_name']
    return { error: 'script_name required' } unless script_name

    variables = params['variables'] || {}
    result = call_ha_script(script_name, variables)

    success = result.include?('✅')
    { action: 'run_script', script: script_name, success: success }
  end

  def self.call_ha_service_action(params)
    domain = params['domain']
    service = params['service']
    return { error: 'domain and service required' } unless domain && service

    service_data = params['data'] || {}
    result = call_ha_service(domain, service, service_data)

    success = result.include?('✅')
    { action: 'call_service', service: "#{domain}.#{service}", success: success }
  end

  def self.format_parallel_results(results)
    successful = results.reject { |r| r[:error] }
    failed = results.select { |r| r[:error] }

    output = []

    if successful.any?
      output << "✅ Completed #{successful.length} actions:"
      successful.each do |result|
        output << format_single_result(result)
      end
    end

    if failed.any?
      output << "⚠️ Failed #{failed.length} actions:"
      failed.each do |result|
        output << "  - #{result[:error]}"
      end
    end

    output.join("\n")
  end

  def self.format_single_result(result)
    case result[:action]
    when 'speak'
      "  - Spoke: \"#{result[:message]}\""
    when 'awtrix_display'
      "  - Displayed: \"#{result[:text]}\""
    else
      if result[:entity_id]
        "  - #{result[:entity_id]}: #{result[:value]}#{result[:unit]}"
      else
        "  - #{result.to_json}"
      end
    end
  end
end
