# frozen_string_literal: true

module Services
  module Conversation
    # Executes tool calls from an LLM response and handles errors.
    class ToolExecutionEngine
      def initialize(tool_executor: Services::ToolExecutor, logger: Services::Logging::SimpleLogger)
        @tool_executor = tool_executor
        @logger = logger
      end

      def execute_tool_calls(llm_response, session_id)
        start_time = Time.now
        @logger.info('Starting tool execution cycle', tagged: %i[conversation tools], session_id: session_id, tool_count: llm_response.tool_calls.count)

        tool_results = []
        last_tool_calls = []

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
        { tool_results: tool_results, last_tool_calls: last_tool_calls }
      end

      private

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
