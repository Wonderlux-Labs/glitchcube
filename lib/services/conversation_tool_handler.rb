# frozen_string_literal: true

require_relative 'tool_registry_service'
require_relative 'tool_executor'
require_relative 'llm_service'
require_relative 'logger_service'

module Services
  # Handles all tool-related operations for conversations
  class ConversationToolHandler
    def initialize(session:, persona:)
      @session = session
      @persona = persona
    end

    # Load tools for persona, using provided tools if available
    def load_tools_for_persona(provided_tools: nil)
      return provided_tools unless provided_tools.nil? || provided_tools.empty?

      tools = Services::ToolRegistryService.get_tools_for_character(persona)
      puts "🔧 Auto-loaded #{tools&.size || 0} tools for persona '#{persona}'" if debug_mode?
      tools
    end

    # Configure LLM options with tool support
    def configure_llm_options(base_options, tools)
      return base_options if tools.nil? || tools.empty?

      base_options.merge(
        tools: tools,
        tool_choice: base_options[:tool_choice] || 'auto',
        parallel_tool_calls: base_options[:parallel_tool_calls] != false
      )
    end

    # Handle tool calls from LLM response - returns updated LLM response if continuation needed
    def handle_tool_calls(llm_response, messages, llm_options)
      return llm_response unless llm_response.has_tool_calls?

      # Execute the tool calls
      tool_results = execute_tool_calls(llm_response)
      tool_calls_made = extract_tool_names(llm_response)

      # Store the tool calls for logging
      @last_tool_calls = tool_calls_made

      # If we have tool results, continue the conversation with them
      if tool_results && !tool_results.empty?
        continue_with_tool_results(messages, llm_response, tool_results, llm_options)
      else
        llm_response
      end
    end

    # Get the tool calls made during the last execution (for logging)
    def last_tool_calls_made
      @last_tool_calls || []
    end

    private

    attr_reader :session, :persona

    def execute_tool_calls(llm_response)
      tool_calls = llm_response.tool_calls
      return [] if tool_calls.nil? || tool_calls.empty?

      puts "🔧 Executing #{tool_calls.size} tool call(s)..." if debug_mode?

      # Execute tools
      tool_start = Time.now
      results = Services::ToolExecutor.execute(tool_calls, timeout: 10)
      execution_time = ((Time.now - tool_start) * 1000).round

      puts "🔧 Executed #{tool_calls.size} tool calls in #{execution_time}ms" if debug_mode?

      # Log tool execution
      results.each { |result| log_tool_execution(result) }

      results
    rescue StandardError => e
      puts "⚠️ Tool execution failed: #{e.message}"
      puts "Tool execution error: #{e.message}"
      []
    end

    def continue_with_tool_results(messages, initial_response, tool_results, llm_options)
      # Format tool results for conversation
      tool_message = format_tool_results_message(tool_results)

      # Add initial assistant response with tool calls to messages
      assistant_message = {
        role: 'assistant',
        content: initial_response.content || '',
        tool_calls: initial_response.tool_calls
      }
      messages << assistant_message

      # Add tool results as a tool message
      messages << {
        role: 'tool',
        content: tool_message
      }

      # Save tool interaction to session
      save_tool_interaction(initial_response, tool_results)

      # Get final response after tool execution
      follow_up_response = Services::LLMService.complete_with_messages(
        messages: messages,
        **llm_options.except(:tools, :tool_choice) # Don't allow recursive tool calls for now
      )

      puts '🤖 Follow-up LLM call completed' if debug_mode?
      follow_up_response
    rescue StandardError => e
      puts "⚠️ Failed to continue after tool execution: #{e.message}"
      puts "⚠️ Follow-up LLM call failed: #{e.message}" if debug_mode?

      # Return original response if continuation fails
      initial_response
    end

    def save_tool_interaction(initial_response, tool_results)
      return unless session

      # Save assistant message with tool calls
      session.add_message(
        role: 'assistant',
        content: initial_response.content || '[Tool calls]',
        persona: persona,
        tool_calls: initial_response.tool_calls
      )

      # Save tool results message
      tool_message = format_tool_results_message(tool_results)
      session.add_message(
        role: 'tool',
        content: tool_message,
        persona: persona
      )
    rescue StandardError => e
      puts "Warning: Could not save tool interaction: #{e.message}"
    end

    def format_tool_results_message(tool_results)
      return 'No tool results available.' if tool_results.empty?

      formatted = tool_results.map do |result|
        if result[:success]
          "#{result[:tool_name]}: #{result[:result]}"
        else
          "#{result[:tool_name]} failed: #{result[:error]}"
        end
      end

      formatted.join("\n")
    end

    def extract_tool_names(llm_response)
      llm_response.tool_calls&.map do |tc|
        tc.dig(:function, :name) || tc.dig('function', 'name')
      end&.compact || []
    end

    def log_tool_execution(result)
      Services::LoggerService.log_api_call(
        service: 'tool_executor',
        endpoint: result[:tool_name],
        method: 'execute',
        status: result[:success] ? 200 : 500,
        session_id: session.session_id,
        persona: persona
      )
    rescue StandardError => e
      puts "Failed to log tool execution: #{e.message}" if debug_mode?
    end

    def debug_mode?
      GlitchCube.config.debug?
    end
  end
end
