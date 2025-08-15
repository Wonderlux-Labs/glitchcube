# frozen_string_literal: true

require 'securerandom'

module Services
  module Conversation
    class FlowManager
      def initialize(error_handler: ErrorHandler, logger: Logging::SimpleLogger)
        @state_manager = StateManager.new
        @history_manager = HistoryManager.new
        @llm_manager = LlmInteractionManager.new(logger: logger)
        @tool_engine = ToolExecutionEngine.new(logger: logger)
        @response_processor = ResponseProcessor.new(logger: logger)
        @error_handler = error_handler
        @logger = logger
      end

      def process_conversation(message:, context: {}, persona: nil)
        start_time = Time.now
        persona_name = persona || context[:persona] || PersonaStateService.get_current_persona
        persona_instance = Personas::BasePersona.create(persona_name, context)

        context[:tools] ||= persona_instance.tool_schemas
        context[:session_id] ||= SecureRandom.uuid

        session = @state_manager.create_or_get_session(context[:session_id], context.merge(persona: persona_name))

        @logger.info('Starting conversation processing', tagged: %i[conversation flow], session_id: session.session_id, persona: persona_name, has_message: !message.to_s.strip.empty?)

        # Centralized error handling for the entire conversation flow
        begin
          llm_response, last_tool_calls = execute_conversation_cycle(message, session, persona_instance, context)
          response_data = @response_processor.process_response(llm_response, persona_instance, session.session_id)

          record_assistant_response(session, response_data, llm_response, last_tool_calls, persona_name, start_time)

          final_result = build_final_result(response_data, session, llm_response, context, persona_name)
          @logger.info('Conversation processing finished', tagged: %i[conversation flow], session_id: session.session_id, persona: persona_name, response_text_length: final_result[:response].to_s.length, duration_ms: ((Time.now - start_time) * 1000).round)
          final_result
        rescue StandardError => e
          # Delegate error handling to the centralized handler
          @logger.log_error(error: e, message: 'Error during conversation processing', session_id: session.session_id, persona: persona_name)
          @error_handler.handle(e, session: session, message: message, persona: persona_name, context: context)
        end
      end

      private

      def execute_conversation_cycle(message, session, persona_instance, context)
        context = Memory::ContextEnrichmentService.enrich(context)
        system_prompt = @llm_manager.build_system_prompt(persona_instance, context)
        conversation_history = @history_manager.get_conversation_context(session)

        messages = @llm_manager.prepare_messages(conversation_history, system_prompt, message)
        @state_manager.record_message(session: session, role: 'user', content: message, persona: persona_instance.name)

        max_iterations = GlitchCube.config.tool_retry&.max_iterations || 2
        iteration = 1
        last_tool_calls = []
        llm_response = nil

        while iteration <= max_iterations
          @logger.info("Starting tool calling iteration #{iteration}/#{max_iterations}", tagged: %i[conversation tools iteration], session_id: session.session_id)

          # Build context for this iteration
          iteration_context = build_iteration_context(context, iteration, max_iterations)
          llm_options = build_llm_options(iteration_context, session.session_id)

          # Validate message structure before sending to OpenRouter
          validate_message_structure(messages)

          # Log EXACTLY what we're sending to OpenRouter for debugging
          @logger.info("ITERATION #{iteration} - Sending messages to LLM",
                       tagged: %i[conversation tools messages],
                       session_id: session.session_id,
                       model: llm_options[:model],
                       message_count: messages.count,
                       has_tools: !llm_options[:tools].nil?,
                       messages_structure: messages.map do |m|
                         {
                           role: m[:role] || m['role'],
                           has_content: !m[:content].nil? && !m['content'].nil?,
                           content_preview: (m[:content] || m['content'] || '').to_s[0..50],
                           has_tool_calls: m.key?(:tool_calls) || m.key?('tool_calls'),
                           has_tool_call_id: m.key?(:tool_call_id) || m.key?('tool_call_id'),
                           is_tool_role: m[:role] == 'tool' || m['role'] == 'tool'
                         }
                       end)

          # Make LLM call with schema retry logic
          llm_response = call_llm_with_schema_retry(messages, llm_options, session.session_id)

          # If no tool calls, we're done
          unless llm_response.tool_calls?
            @logger.info("No tool calls in iteration #{iteration}. Ending cycle.", tagged: %i[conversation tools], session_id: session.session_id)
            break
          end

          @logger.info("Executing #{llm_response.tool_calls.count} tool calls in iteration #{iteration}", tagged: %i[conversation tools], session_id: session.session_id, tool_call_count: llm_response.tool_calls.count)

          # Execute tools
          tool_execution_result = @tool_engine.execute_tool_calls(llm_response, session.session_id)
          tool_results = tool_execution_result[:tool_results]
          last_tool_calls = tool_execution_result[:last_tool_calls]
          failed_tool_calls = tool_execution_result[:failed_tool_calls]

          # Create ONE assistant message with proper content (intent + tool summary)
          response_text = llm_response.response_text
          intent = if response_text.nil? || response_text.strip.empty?
                     "I'll help you with that"
                   else
                     response_text
                   end

          tool_summary = create_simple_tool_summary(last_tool_calls)

          # Combine intent and summary in a single, always-valid message
          content = "#{intent}. #{tool_summary}".strip
          content = 'Working on your request...' if content.empty?

          messages << {
            role: 'assistant',
            content: content
          }

          # Check if we should continue to next iteration
          if should_continue_iteration?(failed_tool_calls, iteration, max_iterations)
            @logger.info("Tool failures detected in iteration #{iteration}. Continuing to iteration #{iteration + 1}", tagged: %i[conversation tools iteration], session_id: session.session_id, failed_count: failed_tool_calls.count)

            # Add gentle MCP suggestion if this is the second-to-last iteration
            if iteration == max_iterations - 1
              add_mcp_suggestion_to_messages(messages, failed_tool_calls)
            end

            iteration += 1
          else
            @logger.info('No failures or max iterations reached. Ending tool calling cycle.', tagged: %i[conversation tools], session_id: session.session_id)
            break
          end
        end

        # Final response call if we ended on tool calls
        if llm_response&.tool_calls?
          @logger.info('Making final LLM call after tool iterations.', tagged: %i[conversation tools], session_id: session.session_id)

          # Convert tool execution results to plain English for the final model
          final_messages = convert_tool_history_to_english(messages, last_tool_calls)

          # Validate final messages before sending to non-tool model
          validate_message_structure(final_messages)

          post_tool_context = context.dup
          post_tool_context[:tools] = nil
          llm_response = call_llm_with_schema_retry(final_messages, build_llm_options(post_tool_context, session.session_id, with_tools: false), session.session_id)
        end

        [llm_response, last_tool_calls]
      end

      def record_assistant_response(session, response_data, llm_response, last_tool_calls, persona_name, start_time)
        @state_manager.record_message(
          session: session,
          role: 'assistant',
          content: response_data[:response],
          persona: persona_name,
          model_used: llm_response.model,
          prompt_tokens: llm_response.usage[:prompt_tokens],
          completion_tokens: llm_response.usage[:completion_tokens],
          cost: llm_response.cost,
          response_time_ms: ((Time.now - start_time) * 1000).round,
          metadata: {
            continue_conversation: response_data[:continue_conversation],
            tool_calls: last_tool_calls,
            inner_thoughts: response_data[:inner_thoughts]
          }
        )
      end

      def build_llm_options(context, session_id, with_tools: true)
        options = {
          model: @llm_manager.select_appropriate_model(context, session_id),
          temperature: context[:temperature] || GlitchCube.config.conversation&.temperature || 0.8,
          max_tokens: context[:max_tokens] || GlitchCube.config.conversation&.max_tokens || GlitchCube.config.ai.max_tokens,
          timeout: context[:timeout] || GlitchCube.config.conversation&.completion_timeout || 60
        }

        # Simple logic: use tools if available, otherwise rely on prompt-based structured output
        use_tools = with_tools && context[:tools].present? && !context[:tools].empty?

        if use_tools
          @logger.debug('Using native tool calling', tagged: %i[conversation tools], tools_count: context[:tools].count)
          options[:tools] = context[:tools]
          options[:tool_choice] = 'auto'
          options[:max_tokens] = context[:max_tokens] || GlitchCube.config.ai.max_tool_tokens
        else
          @logger.debug('Using prompt-based structured output', tagged: %i[conversation structured_output])
        end

        @logger.debug('Built LLM options', tagged: %i[conversation llm], session_id: session_id, model: options[:model], temperature: options[:temperature], has_tools: !options[:tools].nil?)
        options
      end

      def build_final_result(response_data, session, llm_response, context, persona_name)
        {
          response: response_data[:response],
          conversation_id: session.session_id,
          session_id: session.session_id,
          persona: persona_name,
          model: llm_response.model,
          cost: llm_response.cost,
          tokens: llm_response.usage,
          continue_conversation: response_data[:continue_conversation],
          tts_handled: false,
          voice_interaction: context[:voice_interaction] || false,
          error: nil
        }
      end

      def should_continue_iteration?(failed_tool_calls, current_iteration, max_iterations)
        return false if failed_tool_calls.empty?
        return false if current_iteration >= max_iterations
        return false unless GlitchCube.config.tool_retry&.enabled
        return false unless GlitchCube.config.tool_retry&.use_mcp_fallback

        # Only continue for Home Assistant related tools
        failed_tool_calls.any? { |call| home_assistant_tool?(call[:function_name]) }
      end

      def build_iteration_context(context, iteration, max_iterations)
        iteration_context = context.dup

        # On the last iteration, add MCP tool to available tools
        if iteration == max_iterations && GlitchCube.config.tool_retry&.use_mcp_fallback
          @logger.debug('Adding MCP tool to context for final iteration', tagged: %i[conversation tools iteration])

          # Get existing tools and add MCP tool schema
          existing_tools = iteration_context[:tools] || []
          mcp_tool_schema = build_mcp_tool_schema

          # Only add if not already present
          unless existing_tools.any? { |tool| tool.dig('function', 'name') == 'hass_mcp' }
            iteration_context[:tools] = existing_tools + [mcp_tool_schema]
          end
        end

        iteration_context
      end

      def add_mcp_suggestion_to_messages(messages, failed_tool_calls)
        return if failed_tool_calls.empty?

        suggestion_text = build_mcp_suggestion_text(failed_tool_calls)

        messages << {
          role: 'system',
          content: suggestion_text
        }

        @logger.debug('Added MCP suggestion to conversation', tagged: %i[conversation tools mcp_suggestion])
      end

      def build_mcp_suggestion_text(failed_tool_calls)
        first_failure = failed_tool_calls.first

        "I notice some of your tool calls failed (#{first_failure[:error]}). " \
          'You now have access to the hass_mcp tool which can directly interface with Home Assistant. ' \
          'Consider using GetLiveContext first to see all available devices, then try the appropriate MCP function ' \
          '(like HassTurnOn, HassLightSet, etc.) to accomplish your goal.'
      end

      def home_assistant_tool?(tool_name)
        # Tools that interact with Home Assistant and could benefit from MCP fallback
        ha_tools = %w[
          set_light_state set_light_color set_light_brightness
          turn_on_light turn_off_light
          play_media pause_media set_volume
          display_text show_notification
        ]
        ha_tools.include?(tool_name)
      end

      def build_mcp_tool_schema
        {
          'type' => 'function',
          'function' => {
            'name' => 'hass_mcp',
            'description' => 'Execute Home Assistant commands through MCP protocol - supports lights, switches, scenes, media players, and more',
            'parameters' => {
              'type' => 'object',
              'properties' => {
                'mcp_function' => {
                  'type' => 'string',
                  'description' => 'The MCP function to call (e.g., HassTurnOn, HassTurnOff, HassLightSet, GetLiveContext)'
                },
                'mcp_params' => {
                  'type' => 'object',
                  'description' => 'Parameters for the MCP function (varies by function)'
                }
              },
              'required' => ['mcp_function']
            }
          }
        }
      end

      # Call LLM with retry logic for JSON schema errors
      def call_llm_with_schema_retry(messages, llm_options, session_id)
        @llm_manager.call_llm(messages: messages, llm_options: llm_options, session_id: session_id)
      rescue ::Services::Llm::LLMService::JSONSchemaError => e
        @logger.warn('JSON schema error, retrying without response_format', tagged: %i[conversation llm retry], session_id: session_id, error: e.message)

        # Remove response_format and retry
        retry_options = llm_options.dup
        retry_options.delete(:response_format)

        @llm_manager.call_llm(messages: messages, llm_options: retry_options, session_id: session_id)
      end

      # Create simple tool summary for immediate addition to conversation
      def create_simple_tool_summary(tool_calls)
        return "I'm working on that..." if tool_calls.nil? || tool_calls.empty?

        results = tool_calls.map do |tc|
          # Only check basic success/failure - ignore all data/emojis
          if tc[:result].is_a?(Hash) && tc[:result][:success] == false
            "❌ #{tc[:tool_name]}: failed"
          else
            "✅ #{tc[:tool_name]}: completed"
          end
        end

        "Actions completed: #{results.join(', ')}"
      end

      # Validate message structure before sending to OpenRouter
      def validate_message_structure(messages)
        prev_role = nil

        messages.each do |msg|
          # No empty content (proper Ruby check)
          content = msg[:content] || msg['content']
          if content.nil? || content.to_s.strip.empty?
            @logger.error('Empty content in message', tagged: %i[conversation validation], role: msg[:role] || msg['role'])
            msg[:content] = 'Processing...'
          end

          # No consecutive assistant messages
          current_role = msg[:role] || msg['role']
          if current_role == 'assistant' && prev_role == 'assistant'
            @logger.error('Consecutive assistant messages detected', tagged: %i[conversation validation])
          end

          prev_role = current_role
        end
      end

      # Convert tool call history to simple text for non-tool models
      def convert_tool_history_to_english(messages, executed_tools)
        # Handle nil or empty inputs
        return [] if messages.nil? || messages.empty?

        executed_tools ||= []

        # 1. Filter out the raw tool messages that cause 400 errors
        # CRITICAL: Check both symbol AND string keys (OpenRouter returns string keys)
        messages.reject do |msg|
          msg.key?(:tool_calls) || msg.key?(:tool_call_id) ||
            msg.key?('tool_calls') || msg.key?('tool_call_id') ||
            msg['role'] == 'tool' || msg[:role] == 'tool'
        end

        # 2. Tool summary already added during iteration - no need to add again
      end
    end
  end
end
