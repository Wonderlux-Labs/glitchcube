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
          @logger.log_error(error: e, message: 'Error during conversation processing', session_id: session.session_id, persona: persona_name, backtrace: e.backtrace)
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

          # Add LLM response and tool results to conversation
          messages << llm_response.message_data
          messages.concat(tool_results)

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
          post_tool_context = context.dup
          post_tool_context[:tools] = nil
          llm_response = call_llm_with_schema_retry(messages, build_llm_options(post_tool_context, session.session_id, with_tools: false), session.session_id)
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
          timeout: context[:timeout] || GlitchCube.config.conversation&.completion_timeout || 20
        }

        if with_tools && context[:tools].present? && !context[:tools].empty?
          options[:tools] = context[:tools]
          options[:tool_choice] = 'auto'
          options[:max_tokens] = context[:max_tokens] || GlitchCube.config.ai.max_tool_tokens
        elsif (response_schema = @llm_manager.get_response_schema(context)) && Services::Llm::LLMService.supports_json_schema?(options[:model])
          options[:response_format] = Schemas::ConversationResponseSchema.to_openrouter_format(response_schema)
        end

        @logger.debug('Built LLM options', tagged: %i[conversation llm], session_id: session_id, model: options[:model], temperature: options[:temperature], has_tools: !options[:tools].nil?, has_response_format: !options[:response_format].nil?)
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
      rescue Services::Llm::LLMService::JSONSchemaError => e
        @logger.warn('JSON schema error, retrying without response_format', tagged: %i[conversation llm retry], session_id: session_id, error: e.message)

        # Remove response_format and retry
        retry_options = llm_options.dup
        retry_options.delete(:response_format)

        @llm_manager.call_llm(messages: messages, llm_options: retry_options, session_id: session_id)
      end
    end
  end
end
