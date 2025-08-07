# frozen_string_literal: true

require 'concurrent'

# Enhancements for conversation module with optimized sensor collection and utilities
module ConversationEnhancements

  # Enrich context with Home Assistant sensor data (optimized for art installation)
  def enrich_context_with_sensors(context)
    return context unless context[:include_sensors]

    begin
      client = HomeAssistantClient.new

      # Get key sensor values in parallel with fast timeouts for art installation
      sensor_futures = {
        battery: Concurrent::Future.execute do
          client.battery_level
        rescue StandardError
          nil
        end,
        temperature: Concurrent::Future.execute do
          client.temperature
        rescue StandardError
          nil
        end,
        motion: Concurrent::Future.execute do
          client.motion_detected?
        rescue StandardError
          nil
        end
      }

      # Collect results with fast timeout (500ms - art installation needs responsiveness)
      sensor_data = {}
      sensor_futures.each do |key, future|
        sensor_data[key] = future.value(0.5) # 500ms timeout
      rescue StandardError
        sensor_data[key] = nil
      end

      context[:sensor_data] = sensor_data
      context[:sensor_summary] = format_sensor_summary(sensor_data)
    rescue StandardError => e
      # Silent failure - art installation should continue even if sensors fail
      context[:sensor_error] = e.message
    end

    context
  end

  # Format sensor data for context
  def format_sensor_summary(sensor_data)
    parts = []
    parts << "Battery: #{sensor_data[:battery]}%" if sensor_data[:battery]
    parts << "Temp: #{sensor_data[:temperature]}°C" if sensor_data[:temperature]
    parts << "Motion: #{sensor_data[:motion] ? 'detected' : 'none'}" unless sensor_data[:motion].nil?

    parts.empty? ? nil : parts.join(', ')
  end

  # Simple error recovery for development environment only
  def attempt_connection_recovery
    return false unless ENV['RACK_ENV'] == 'development'
    
    # Try to restart mock services in development
    system('docker-compose restart homeassistant 2>/dev/null')
    sleep(1) # Reduced from 2 seconds
    true
  rescue StandardError
    false
  end

  # Add a message to conversation tracking
  def add_message_to_conversation(conversation, message_data)
    conversation[:messages] ||= []
    message_data[:timestamp] = Time.current
    conversation[:messages] << message_data

    # Update conversation cost and token tracking
    conversation[:total_cost] = (conversation[:total_cost] || 0.0) + message_data[:cost] if message_data[:cost]

    if message_data[:prompt_tokens] && message_data[:completion_tokens]
      conversation[:total_tokens] = (conversation[:total_tokens] || 0) +
                                    message_data[:prompt_tokens] + message_data[:completion_tokens]
    end

    message_data
  end

  # Update conversation totals from all messages
  def update_conversation_totals(conversation)
    messages = conversation[:messages] || []

    total_cost = messages.sum { |m| m[:cost] || 0.0 }
    total_tokens = messages.sum { |m| (m[:prompt_tokens] || 0) + (m[:completion_tokens] || 0) }

    conversation[:total_cost] = total_cost
    conversation[:total_tokens] = total_tokens

    conversation
  end

  # Simple retry wrapper for critical operations (art installation optimized)
  def with_retry(operation_name, max_retries: 2)
    attempts = 0
    
    begin
      attempts += 1
      yield
    rescue StandardError => e
      if attempts < max_retries
        # Quick retry for art installation - no long waits
        sleep(0.5)
        retry
      else
        # Log error but don't expose full details to avoid breaking the installation
        puts "⚠️ #{operation_name} failed after #{attempts} attempts: #{e.message[0..100]}"
        raise e
      end
    end
  end
end
