# frozen_string_literal: true

require 'timeout'
require 'concurrent'

module Services
  # Executes tool calls parsed from LLM responses
  class ToolExecutor
    class ExecutionError < StandardError; end
    class ToolNotFoundError < ExecutionError; end
    class ToolTimeoutError < ExecutionError; end

    DEFAULT_TIMEOUT = 10 # seconds

    class << self
      # Execute a single tool call or array of tool calls
      #
      # @param tool_calls [Hash, Array<Hash>] Tool call(s) to execute
      # @param options [Hash] Execution options
      # @return [Array<Hash>] Results of tool execution
      def execute(tool_calls, options = {})
        calls = Array(tool_calls)
        return [] if calls.empty?

        # Check if we should execute in parallel
        if options[:parallel] != false && calls.size > 1
          execute_parallel(calls, options)
        else
          execute_sequential(calls, options)
        end
      end

      # Execute tool calls sequentially
      #
      # @param tool_calls [Array<Hash>] Tool calls to execute
      # @param options [Hash] Execution options
      # @return [Array<Hash>] Results
      def execute_sequential(tool_calls, options)
        tool_calls.map do |call|
          execute_single(call, options)
        end
      end

      # Execute tool calls in parallel
      #
      # @param tool_calls [Array<Hash>] Tool calls to execute
      # @param options [Hash] Execution options
      # @return [Array<Hash>] Results
      def execute_parallel(tool_calls, options)
        futures = tool_calls.map do |call|
          Concurrent::Future.execute do
            execute_single(call, options)
          end
        end

        # Wait for all futures and collect results
        futures.map(&:value)
      end

      # Execute a single tool call
      #
      # @param tool_call [Hash] Tool call to execute
      # @param options [Hash] Execution options
      # @return [Hash] Execution result
      def execute_single(tool_call, options = {})
        tool_name = tool_call[:name] || tool_call['name']
        tool_args = tool_call[:arguments] || tool_call['arguments'] || {}
        tool_id = tool_call[:id] || tool_call['id'] || "tool_#{SecureRandom.hex(4)}"

        # Find and validate tool
        tool_class = find_tool_class(tool_name)
        
        if tool_class.nil?
          return error_result(tool_id, tool_name, "Tool not found: #{tool_name}")
        end

        # Execute with timeout
        timeout_seconds = options[:timeout] || DEFAULT_TIMEOUT
        
        result = Timeout.timeout(timeout_seconds) do
          execute_tool_safely(tool_class, tool_args)
        end

        # Return successful result
        {
          tool_call_id: tool_id,
          tool_name: tool_name,
          success: true,
          result: result,
          executed_at: Time.now.iso8601
        }

      rescue Timeout::Error
        error_result(tool_id, tool_name, "Tool execution timed out after #{timeout_seconds} seconds")
      rescue StandardError => e
        error_result(tool_id, tool_name, "Execution error: #{e.message}")
      end

      # Execute tool with error handling
      #
      # @param tool_class [Class] The tool class
      # @param arguments [Hash] Tool arguments
      # @return [String] Tool result
      def execute_tool_safely(tool_class, arguments)
        # Validate tool has required method
        unless tool_class.respond_to?(:call)
          raise ExecutionError, "Tool #{tool_class} does not implement .call method"
        end

        # Convert arguments to symbols if needed
        args = normalize_arguments(arguments)

        # Call the tool
        result = tool_class.call(**args)

        # Ensure result is a string
        result.to_s
      rescue ArgumentError => e
        # Handle missing required arguments
        raise ExecutionError, "Invalid arguments for tool: #{e.message}"
      end

      # Normalize arguments for tool execution
      #
      # @param arguments [Hash] Raw arguments
      # @return [Hash] Normalized arguments with symbol keys
      def normalize_arguments(arguments)
        return {} unless arguments.is_a?(Hash)

        arguments.transform_keys do |key|
          key.to_s.to_sym
        end
      end

      # Find tool class by name
      #
      # @param tool_name [String] Name of the tool
      # @return [Class, nil] Tool class or nil
      def find_tool_class(tool_name)
        # Standard naming convention: tool_name -> ToolNameTool
        class_name = tool_name.split('_').map(&:capitalize).join + 'Tool'
        
        # Try root namespace first
        if Object.const_defined?(class_name)
          return Object.const_get(class_name)
        end

        # Try Tools namespace
        namespaced = "Tools::#{class_name}"
        if Object.const_defined?(namespaced)
          return Object.const_get(namespaced)
        end

        # Try exact match (if already properly formatted)
        if Object.const_defined?(tool_name)
          return Object.const_get(tool_name)
        end

        # Load tool file if not loaded
        load_tool_file(tool_name)

        # Try again after loading
        if Object.const_defined?(class_name)
          Object.const_get(class_name)
        else
          nil
        end
      rescue NameError => e
        Rails.logger.warn "Failed to find tool class for #{tool_name}: #{e.message}" if defined?(Rails)
        nil
      end

      # Load tool file if it exists
      #
      # @param tool_name [String] Name of the tool
      def load_tool_file(tool_name)
        # Look for tool file
        if defined?(Rails)
          tool_file = Rails.root.join('lib', 'tools', "#{tool_name}_tool.rb")
        else
          # In test environment, use relative path
          tool_file = File.expand_path("../../tools/#{tool_name}_tool.rb", __FILE__)
        end
        
        if File.exist?(tool_file)
          require tool_file
        else
          # Try alternate path
          if defined?(Rails)
            alt_file = Rails.root.join('lib', 'tools', "#{tool_name}.rb")
          else
            alt_file = File.expand_path("../../tools/#{tool_name}.rb", __FILE__)
          end
          require alt_file if File.exist?(alt_file)
        end
      rescue LoadError => e
        puts "Could not load tool file for #{tool_name}: #{e.message}" if ENV['DEBUG']
      end

      # Create error result
      #
      # @param tool_id [String] Tool call ID
      # @param tool_name [String] Tool name
      # @param error_message [String] Error message
      # @return [Hash] Error result
      def error_result(tool_id, tool_name, error_message)
        {
          tool_call_id: tool_id,
          tool_name: tool_name,
          success: false,
          error: error_message,
          executed_at: Time.now.iso8601
        }
      end

      # Format results for conversation
      #
      # @param results [Array<Hash>] Tool execution results
      # @return [String] Formatted results for LLM
      def format_for_conversation(results)
        return "No tool results" if results.empty?

        formatted = results.map do |result|
          if result[:success]
            "Tool: #{result[:tool_name]}\nResult: #{result[:result]}"
          else
            "Tool: #{result[:tool_name]}\nError: #{result[:error]}"
          end
        end

        formatted.join("\n\n")
      end

      # Log tool execution
      #
      # @param tool_name [String] Tool name
      # @param success [Boolean] Whether execution succeeded
      # @param duration_ms [Integer] Execution time in milliseconds
      def log_execution(tool_name, success, duration_ms)
        Services::LoggerService.log_api_call(
          service: 'tool_executor',
          endpoint: tool_name,
          method: 'execute',
          status: success ? 200 : 500,
          duration: duration_ms
        )
      rescue StandardError => e
        Rails.logger.warn "Failed to log tool execution: #{e.message}" if defined?(Rails)
      end
    end
  end
end