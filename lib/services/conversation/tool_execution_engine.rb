# frozen_string_literal: true

module ::Services
  module Conversation
    # Executes tool calls from an LLM response and handles errors.
    class ToolExecutionEngine
      def initialize(tool_executor: ToolExecutor, logger: Logging::SimpleLogger)
        @tool_executor = tool_executor
        @logger = logger
      end

      def execute_tool_calls(llm_response, session_id)
        start_time = Time.now
        @logger.info('Starting tool execution cycle',
                     tagged: %i[conversation tools],
                     session_id: session_id,
                     tool_count: llm_response.tool_calls.count,
                     pattern: GlitchCube.config.tool_calling_pattern)

        # Bifurcation point: Choose execution pattern
        if GlitchCube.config.tool_calling_pattern == :back_to_hass
          @logger.info('Using Home Assistant tool proxy for execution',
                       tagged: %i[conversation tools hass_proxy],
                       session_id: session_id)
          return execute_via_home_assistant(llm_response, session_id)
        end

        @logger.debug('Using default tool execution pattern',
                      tagged: %i[conversation tools default],
                      session_id: session_id)

        tool_results = []
        last_tool_calls = []
        failed_tool_calls = []

        llm_response.tool_calls.each_with_index do |tool_call, index|
          function_call = llm_response.function_calls[index]
          function_name = function_call[:name]

          # Using a begin-rescue block to catch any argument parsing errors
          begin
            arguments = llm_response.function_arguments_for(function_name)

            if arguments.nil?
              message = 'Could not parse arguments for tool call, skipping.'
              @logger.warn(message, tagged: %i[conversation tools json_parse], tool: function_name, session_id: session_id)
              # Add an error result to tool_results to indicate failure
              tool_results << create_error_result(tool_call, function_name, message)
              next
            end

            @logger.debug("Executing tool: #{function_name}", tagged: %i[conversation tools], session_id: session_id, tool_name: function_name, arguments: arguments)
            tool_call_hash = { name: function_name, arguments: arguments }
            results = @tool_executor.execute([tool_call_hash])
            result = results.first
            @logger.debug("Tool execution result for #{function_name}", tagged: %i[conversation tools], session_id: session_id, tool_name: function_name, result: result)

            # Check if tool execution failed (discovery failure, etc.)
            if result.is_a?(Hash) && result[:success] == false
              @logger.warn("Tool execution failed: #{result[:error]}", tagged: %i[conversation tools tool_failure], session_id: session_id, tool_name: function_name, error: result[:error])

              # Store failed tool call for potential retry
              unless function_name == 'hass_mcp' # Don't retry MCP tool failures
                failed_tool_calls << {
                  tool_call: tool_call,
                  function_name: function_name,
                  arguments: arguments,
                  error: result[:error]
                }
              end
              # Still add to tool_results so LLM can see the failure and respond
            end

            # Store the last tool calls for context
            last_tool_calls << {
              tool_name: function_name,
              arguments: arguments,
              result: result
            }

            tool_content = result.is_a?(Hash) ? result.to_json : result.to_s

            tool_results << {
              tool_call_id: tool_call[:id],
              role: 'tool',
              name: function_name,
              content: tool_content
            }
          rescue StandardError => e
            @logger.log_error(error: e, message: "Error executing tool: #{function_name}", session_id: session_id, tool_name: function_name)
            # Re-raise as a custom error to be handled by the global error handler
            raise Errors::ToolExecutionError.new(
              "Error executing tool: #{function_name}",
              tool_name: function_name,
              original_error: e
            )
          end
        end

        duration_ms = ((Time.now - start_time) * 1000).round
        @logger.info("Finished tool execution cycle in #{duration_ms}ms", tagged: %i[conversation tools], session_id: session_id, duration_ms: duration_ms)

        # Return results with info about failures for retry handling
        {
          tool_results: tool_results,
          last_tool_calls: last_tool_calls,
          failed_tool_calls: failed_tool_calls
        }
      end

      private

      def execute_via_home_assistant(llm_response, session_id)
        proxy = HomeAssistantToolProxy.new(logger: @logger)
        proxy.execute_via_hass(llm_response, session_id)
      end

      def create_error_result(tool_call, function_name, error_message)
        {
          tool_call_id: tool_call[:id],
          role: 'tool',
          name: function_name,
          content: { error: error_message }.to_json
        }
      end
    end
  end
end
