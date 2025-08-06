# frozen_string_literal: true

require 'concurrent'

# Enhancements for conversation module with parallel processing and auto-recovery
module ConversationEnhancements
  # Execute multiple tool calls in parallel
  def execute_parallel_tools(tool_calls)
    return [] if tool_calls.nil? || tool_calls.empty?

    futures = tool_calls.map do |tool_call|
      Concurrent::Future.execute do
        execute_single_tool(tool_call)
      end
    end

    # Collect results with timeout
    results = []
    futures.each_with_index do |future, index|
      result = future.value(5) # 5 second timeout per tool
      results << if result.nil?
                   # Timeout occurred - future.value returns nil on timeout
                   {
                     tool: tool_calls[index][:function][:name],
                     error: 'Tool execution timed out',
                     retry_attempted: false
                   }
                 else
                   result
                 end
    rescue StandardError => e
      results << {
        tool: tool_calls[index][:function][:name],
        error: e.message,
        retry_attempted: false
      }
    end

    results
  end

  # Execute a single tool call with retry logic
  def execute_single_tool(tool_call)
    tool_name = tool_call[:function][:name]
    arguments = JSON.parse(tool_call[:function][:arguments])

    # Find the tool class
    tool_class = find_tool_class(tool_name)
    return { error: "Tool not found: #{tool_name}" } unless tool_class

    # Try to execute with retries
    execute_with_retry(3) do
      result = tool_class.call(**arguments.transform_keys(&:to_sym))
      {
        tool: tool_name,
        result: result,
        success: true
      }
    end
  rescue StandardError => e
    {
      tool: tool_name,
      error: e.message,
      success: false
    }
  end

  # Execute with exponential backoff retry
  def execute_with_retry(max_attempts, initial_delay: 0.5)
    attempt = 0
    delay = initial_delay

    begin
      attempt += 1
      yield
    rescue StandardError => e
      raise e unless attempt < max_attempts

      sleep(delay)
      delay *= 2 # Exponential backoff
      retry
    end
  end

  # Find tool class by name
  def find_tool_class(tool_name)
    case tool_name
    when 'home_assistant'
      HomeAssistantTool
    when 'home_assistant_parallel'
      HomeAssistantParallelTool
    when 'test_tool'
      TestTool
    else
      # Try to constantize the tool name
      tool_class_name = tool_name.split('_').map(&:capitalize).join
      begin
        Object.const_get(tool_class_name)
      rescue StandardError
        nil
      end
    end
  end

  # Enrich context with Home Assistant sensor data
  def enrich_context_with_sensors(context)
    return context unless context[:include_sensors]

    begin
      client = HomeAssistantClient.new

      # Get key sensor values in parallel
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

      # Collect results with timeout
      sensor_data = {}
      sensor_futures.each do |key, future|
        sensor_data[key] = future.value(1) # 1 second timeout
      rescue StandardError
        sensor_data[key] = nil
      end

      context[:sensor_data] = sensor_data
      context[:sensor_summary] = format_sensor_summary(sensor_data)
    rescue StandardError => e
      puts "Failed to enrich context with sensors: #{e.message}"
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

  # Auto-fix common errors before failing
  def attempt_error_recovery(error, context = {})
    case error
    when /connection refused/i
      attempt_connection_recovery
    when /timeout/i
      attempt_timeout_recovery(context)
    when /rate limit/i
      attempt_rate_limit_recovery
    when /authentication/i
      attempt_auth_recovery
    else
      false
    end
  end

  # Try to recover from connection errors
  def attempt_connection_recovery
    puts '🔧 Attempting to recover from connection error...'

    # Check if services are running
    if ENV['RACK_ENV'] == 'development'
      # Try to restart mock services
      system('docker-compose restart homeassistant 2>/dev/null')
      sleep(2)
      true
    else
      false
    end
  end

  # Try to recover from timeout errors
  def attempt_timeout_recovery(context)
    puts '🔧 Attempting to recover from timeout...'

    # Increase timeout for next attempt
    context[:timeout] = (context[:timeout] || 30) * 1.5
    context[:timeout] = [context[:timeout], 60].min # Cap at 60 seconds

    true
  end

  # Try to recover from rate limit errors
  def attempt_rate_limit_recovery
    puts '🔧 Rate limited - waiting before retry...'
    sleep(5)
    true
  end

  # Try to recover from auth errors
  def attempt_auth_recovery
    puts '🔧 Attempting to refresh authentication...'

    # In production, could refresh tokens here
    # For now, just return false
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

  # Create a self-healing wrapper for any operation
  def with_self_healing(operation_name, max_retries: 3)
    attempts = 0
    last_error = nil

    begin
      attempts += 1
      puts "🔄 Attempting #{operation_name} (attempt #{attempts}/#{max_retries})"

      result = yield

      puts "✅ #{operation_name} succeeded"
      return result
    rescue StandardError => e
      last_error = e
      puts "⚠️ #{operation_name} failed: #{e.message}"

      if attempts < max_retries
        # Try to auto-fix the error
        if attempt_error_recovery(e.message, { operation: operation_name })
          puts '🔧 Auto-recovery attempted, retrying...'
        else
          # Manual retry with backoff
          delay = 2**(attempts - 1) # Exponential backoff
          puts "⏳ Waiting #{delay}s before retry..."
          sleep(delay)
        end
        retry
      end
    end

    # All retries exhausted
    puts "❌ #{operation_name} failed after #{attempts} attempts"
    raise last_error
  end
end
