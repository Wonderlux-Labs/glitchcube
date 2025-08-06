# frozen_string_literal: true

require 'concurrent'
require 'json'
require_relative '../home_assistant_client'

# Enhanced Home Assistant tool with parallel execution support
class HomeAssistantParallelTool
  def self.name
    'home_assistant_parallel'
  end

  def self.description
    'Execute multiple Home Assistant actions in parallel for faster response. ' \
    'Supports batch operations like setting multiple lights, getting all sensors, ' \
    'and executing complex sequences. Args: actions (array of {action: string, params: object})'
  end

  def self.call(actions:)
    # Parse actions if it's a JSON string
    actions = JSON.parse(actions) if actions.is_a?(String)
    
    # Ensure actions is an array
    actions = [actions] unless actions.is_a?(Array)
    
    client = HomeAssistantClient.new
    
    # Execute all actions in parallel
    results = Concurrent::Array.new
    futures = actions.map do |action_spec|
      Concurrent::Future.execute do
        execute_single_action(client, action_spec)
      end
    end
    
    # Wait for all futures to complete (with timeout)
    futures.each_with_index do |future, index|
      begin
        result = future.value(3) # 3 second timeout per action
        if result.nil?
          # Timeout occurred - future.value returns nil on timeout
          results[index] = { error: "Action #{index} timed out", action: actions[index] }
        else
          results[index] = result
        end
      rescue => e
        results[index] = { error: e.message, action: actions[index] }
      end
    end
    
    format_parallel_results(results)
  rescue => e
    "Error executing parallel actions: #{e.message}"
  end

  private

  def self.execute_single_action(client, action_spec)
    action = action_spec['action'] || action_spec[:action]
    params = action_spec['params'] || action_spec[:params] || {}
    
    case action
    when 'get_sensor'
      get_sensor_value(client, params)
    when 'set_light'
      set_light_state(client, params)
    when 'speak'
      speak_message(client, params)
    when 'awtrix_display'
      display_on_awtrix(client, params)
    when 'run_script'
      run_ha_script(client, params)
    when 'call_service'
      call_ha_service(client, params)
    else
      { error: "Unknown action: #{action}" }
    end
  rescue => e
    { error: "Action '#{action}' failed: #{e.message}" }
  end

  def self.get_sensor_value(client, params)
    entity_id = params['entity_id']
    return { error: 'entity_id required for get_sensor' } unless entity_id
    
    state = client.state(entity_id)
    {
      entity_id: entity_id,
      value: state['state'],
      unit: state.dig('attributes', 'unit_of_measurement'),
      friendly_name: state.dig('attributes', 'friendly_name')
    }
  end

  def self.set_light_state(client, params)
    entity_id = params['entity_id'] || 'light.glitch_cube'
    
    if params['state'] == 'off'
      client.turn_off_light(entity_id)
      { entity_id: entity_id, state: 'off' }
    else
      brightness = params['brightness']
      rgb_color = params['rgb_color']
      client.set_light(entity_id, brightness: brightness, rgb_color: rgb_color)
      { entity_id: entity_id, state: 'on', brightness: brightness, rgb_color: rgb_color }
    end
  end

  def self.speak_message(client, params)
    message = params['message']
    return { error: 'message required for speak' } unless message
    
    entity_id = params['entity_id'] || 'media_player.square_voice'
    success = client.speak(message, entity_id: entity_id)
    
    { action: 'speak', message: message, success: success }
  end

  def self.display_on_awtrix(client, params)
    text = params['text']
    return { error: 'text required for AWTRIX display' } unless text
    
    color = params['color'] || [255, 255, 255]
    duration = params['duration'] || 5
    rainbow = params['rainbow'] || false
    
    success = client.awtrix_display_text(text, color: color, duration: duration, rainbow: rainbow)
    
    { action: 'awtrix_display', text: text, success: success }
  end

  def self.run_ha_script(client, params)
    script_name = params['script_name']
    return { error: 'script_name required' } unless script_name
    
    variables = params['variables'] || {}
    response = client.call_service('script', script_name, variables)
    
    { action: 'run_script', script: script_name, success: !response.nil? }
  end

  def self.call_ha_service(client, params)
    domain = params['domain']
    service = params['service']
    return { error: 'domain and service required' } unless domain && service
    
    service_data = params['data'] || {}
    response = client.call_service(domain, service, service_data)
    
    { action: 'call_service', service: "#{domain}.#{service}", success: !response.nil? }
  end

  def self.format_parallel_results(results)
    successful = results.select { |r| !r[:error] }
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