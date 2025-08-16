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
        @conversation_logger = Logging::ConversationLogger.new
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
        # Check if we're using conversation extraction mode
        if GlitchCube.config.tool_execution_mode == :conversation_extraction
          extraction_result = execute_conversation_extraction_cycle(message, session, persona_instance, context)

          # Handle the enhanced return format from extraction cycle
          return extraction_result unless extraction_result.is_a?(Array) && extraction_result.length == 3

          llm_response, mock_tool_calls, action_results_metadata = extraction_result

          # Store action results in context for build_final_result
          if action_results_metadata && action_results_metadata[:action_results_for_hass_api]
            context[:action_results] = action_results_metadata[:action_results_for_hass_api]

            @logger.info('🔄 Restored action results from extraction cycle',
                         tagged: %i[conversation extraction action_results_restore],
                         session_id: session.session_id,
                         action_count: context[:action_results][:actions]&.count || 0)
          end

          return [llm_response, mock_tool_calls]

        end

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
        # Include inner thoughts inline with message text for memory/summarization
        message_content = response_data[:response]
        if response_data[:inner_thoughts] && !response_data[:inner_thoughts].to_s.strip.empty?
          message_content = "[inner thoughts: #{response_data[:inner_thoughts]}] #{message_content}"
        end

        @state_manager.record_message(
          session: session,
          role: 'assistant',
          content: message_content,
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
        # Check if we have action results stored in context
        action_results = context[:action_results]

        @logger.debug('🔍 Context debug in build_final_result',
                      tagged: %i[conversation response context_debug],
                      session_id: session.session_id,
                      context_object_id: context.object_id,
                      action_results_present: !action_results.nil?,
                      action_results_keys: action_results&.keys,
                      context_keys: context.keys)

        if action_results
          @logger.info('🏗️ Building Home Assistant conversation API response with action results',
                       tagged: %i[conversation response home_assistant_api],
                       session_id: session.session_id,
                       has_actions: true)

          # Build Home Assistant conversation API format with proper data structure
          success_actions, failed_actions = categorize_actions(action_results)

          {
            continue_conversation: response_data[:continue_conversation] || false,
            response: {
              response_type: 'action_done',  # Always use action_done for executed actions
              language: 'en',
              data: {
                # Standard Home Assistant fields (arrays of objects)
                targets: build_targets_array(action_results[:actions]),
                success: success_actions,
                failed: failed_actions,
                # Custom data nested cleanly
                custom_data: {
                  execution_summary: action_results[:execution_summary],
                  claude_response: action_results[:claude_results][:message],
                  persona: persona_name,
                  actions_attempted: action_results[:actions]
                }
              },
              speech: {
                plain: {
                  speech: response_data[:response]  # Clean TTS without action details
                }
              }
            },
            conversation_id: session.session_id,
            # Additional metadata for our internal use
            _internal: {
              session_id: session.session_id,
              persona: persona_name,
              model: llm_response.model,
              cost: llm_response.cost,
              tokens: llm_response.usage,
              voice_interaction: context[:voice_interaction] || false
            }
          }
        else
          @logger.info('🏗️ Building standard response without action results',
                       tagged: %i[conversation response standard],
                       session_id: session.session_id,
                       has_actions: false)

          # Standard response for conversations without actions
          {
            continue_conversation: response_data[:continue_conversation] || false,
            response: {
              response_type: 'query_answer',
              language: 'en',
              speech: {
                plain: {
                  speech: response_data[:response]
                }
              }
            },
            conversation_id: session.session_id,
            # Additional metadata for our internal use
            _internal: {
              session_id: session.session_id,
              persona: persona_name,
              model: llm_response.model,
              cost: llm_response.cost,
              tokens: llm_response.usage,
              voice_interaction: context[:voice_interaction] || false
            }
          }
        end
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

      # New conversation extraction cycle - no tool calling, just conversation with action extraction
      def execute_conversation_extraction_cycle(message, session, persona_instance, context)
        # CRITICAL LOOP PREVENTION: Only extract actions from user messages
        # Never run extraction on assistant/system/tool messages to prevent infinite loops
        if context[:message_role] && context[:message_role] != 'user'
          @logger.warn('🚫 Skipping action extraction for non-user message',
                       tagged: %i[conversation extraction loop_prevention],
                       session_id: session.session_id,
                       message_role: context[:message_role],
                       persona: persona_instance.name)

          # Return a simple response without action extraction
          return create_simple_response_without_extraction(message, session, persona_instance, context)
        end

        @logger.info('🎯 Starting conversation extraction cycle (no tool calling)',
                     tagged: %i[conversation extraction],
                     session_id: session.session_id,
                     persona: persona_instance.name,
                     loop_guard: 'user_message_confirmed')

        # Enrich context but modify for conversation-only mode
        context = Memory::ContextEnrichmentService.enrich(context)
        context[:conversation_extraction_mode] = true

        # Build system prompt with tool descriptions but no tool schemas
        system_prompt = @llm_manager.build_system_prompt(persona_instance, context)
        conversation_history = @history_manager.get_conversation_context(session)

        messages = @llm_manager.prepare_messages(conversation_history, system_prompt, message)
        @state_manager.record_message(session: session, role: 'user', content: message, persona: persona_instance.name)

        # Build LLM options WITHOUT tools (conversation only)
        llm_options = build_llm_options_for_conversation(context, session.session_id)

        @logger.info('🗣️ Calling LLM for conversation (no tools)',
                     tagged: %i[conversation extraction llm],
                     session_id: session.session_id,
                     model: llm_options[:model],
                     message_count: messages.count)

        # Get LLM response (pure conversation)
        llm_response = call_llm_with_schema_retry(messages, llm_options, session.session_id)

        @logger.info('✅ Received conversational response from LLM',
                     tagged: %i[conversation extraction response],
                     session_id: session.session_id,
                     response_length: llm_response.response_text&.length || 0)

        # Processing LLM response for action extraction

        # Extract actions from the parsed JSON response
        action_extractor = ActionExtractor.new(logger: @logger)

        # Pass the parsed JSON directly to action extractor if available, otherwise pass response text
        extraction_input = if llm_response.parsed_content.is_a?(Hash)
                             # Using parsed JSON for action extraction
                             llm_response.parsed_content
                           else
                             # Using response text for action extraction
                             llm_response.response_text
                           end

        # Extract actions first
        extracted_actions = action_extractor.extract_actions_only(extraction_input, session.session_id)

        # Store original continue_conversation value before potentially modifying it
        parsed_content = llm_response.parsed_content || {}
        original_continue_conversation = parsed_content['continue_conversation'] || parsed_content[:continue_conversation]

        # Execute actions via Claude if any exist (pass user message for context)
        claude_results = if extracted_actions.any?
                           @logger.info('🎯 Found actions to execute via Claude',
                                        tagged: %i[conversation extraction claude],
                                        session_id: session.session_id,
                                        actions: extracted_actions)

                           action_extractor.execute_actions_via_claude(extracted_actions, session.session_id, message)
                         else
                           @logger.info('ℹ️ No actions to execute',
                                        tagged: %i[conversation extraction claude],
                                        session_id: session.session_id)

                           { success: true, message: 'No actions requested', executed_actions: [] }
                         end

        # 🎭 ENHANCED: Generate persona response that incorporates Claude's feedback
        final_response_text = if extracted_actions.any? && claude_results[:success]
                                generate_persona_response_with_claude_feedback(
                                  persona_instance,
                                  llm_response.response_text,
                                  claude_results,
                                  extracted_actions,
                                  session.session_id
                                )
                              else
                                llm_response.response_text
                              end

        # Build action result for compatibility
        action_result = {
          success: true,
          message: 'Actions extracted and executed via Claude',
          extracted_actions: extracted_actions,
          execution_summary: claude_results[:execution_summary] || 'No actions executed',
          claude_results: claude_results
        }

        @logger.info('🎬 Action extraction and Claude execution completed',
                     tagged: %i[conversation extraction actions claude complete],
                     session_id: session.session_id,
                     success: action_result[:success],
                     action_count: action_result[:extracted_actions]&.count || 0,
                     claude_success: claude_results[:success],
                     claude_message: claude_results[:message])

        # Create mock tool calls for compatibility with existing response processor
        mock_tool_calls = if action_result[:extracted_actions]&.any?
                            [{
                              tool_name: 'claude_conversation_actions',
                              arguments: {
                                actions: action_result[:extracted_actions],
                                claude_execution: claude_results
                              },
                              result: {
                                success: claude_results[:success],
                                message: claude_results[:message],
                                executed_actions: claude_results[:executed_actions] || [],
                                executed_via: 'claude_conversation_agent'
                              }
                            }]
                          else
                            []
                          end

        # Log what we're sending for TTS vs actions
        tts_text = final_response_text  # Use enhanced response text that includes Claude feedback
        actions_for_execution = action_result[:extracted_actions] || []

        # Log final conversation extraction results
        @logger.debug('Final conversation extraction results',
                      tagged: %i[conversation extraction results],
                      session_id: session.session_id,
                      tts_text_length: tts_text&.length || 0,
                      actions_count: actions_for_execution.count)

        @logger.info('🎯 Conversation extraction cycle complete',
                     tagged: %i[conversation extraction complete],
                     session_id: session.session_id,
                     tts_text_length: tts_text&.length || 0,
                     actions_count: actions_for_execution.count,
                     mock_tool_calls_count: mock_tool_calls.count)

        # Store action results for inclusion in Home Assistant conversation API response
        if extracted_actions.any?
          @logger.info('🎯 Storing action results for Home Assistant API response',
                       tagged: %i[conversation extraction action_results_storage],
                       session_id: session.session_id,
                       action_count: extracted_actions.count,
                       claude_success: claude_results[:success])

          # Store action results in context for final response
          context[:action_results] = {
            actions: extracted_actions,
            claude_results: claude_results,
            execution_summary: claude_results[:execution_summary]
          }

          @logger.debug('🔍 Context debug when storing action results',
                        tagged: %i[conversation extraction context_debug],
                        session_id: session.session_id,
                        context_object_id: context.object_id,
                        action_results_stored: true,
                        extracted_actions_count: extracted_actions.count)

          @logger.info('✅ Action results stored for Home Assistant response',
                       tagged: %i[conversation extraction action_results_stored],
                       session_id: session.session_id,
                       action_count: extracted_actions.count)
        end

        # Log the complete conversation flow to conversations.log
        log_conversation_flow_data(
          message: message,
          llm_response: llm_response,
          final_response_text: final_response_text,
          extracted_actions: actions_for_execution,
          claude_results: claude_results,
          session: session,
          persona_instance: persona_instance
        )

        # CRITICAL: Return action results alongside response for final result building
        # This ensures the action results make it to build_final_result even if context gets reset

        # Create enhanced LLM response object with final response text for TTS
        enhanced_llm_response = create_enhanced_llm_response(llm_response, final_response_text)

        return_data = [enhanced_llm_response, mock_tool_calls]

        # Attach action results metadata to the response for reliable access
        if extracted_actions.any?
          return_data << {
            action_results_for_hass_api: {
              actions: extracted_actions,
              claude_results: claude_results,
              execution_summary: claude_results[:execution_summary]
            }
          }
        end

        return_data
      end

      # Create simple response without action extraction (loop prevention)
      def create_simple_response_without_extraction(message, session, persona_instance, context)
        @logger.info('🔄 Creating simple response without action extraction',
                     tagged: %i[conversation extraction loop_prevention simple],
                     session_id: session.session_id,
                     persona: persona_instance.name)

        # Build system prompt and get conversation context
        system_prompt = @llm_manager.build_system_prompt(persona_instance, context)
        conversation_history = @history_manager.get_conversation_context(session)
        messages = @llm_manager.prepare_messages(conversation_history, system_prompt, message)

        # Record the message
        @state_manager.record_message(session: session, role: 'user', content: message, persona: persona_instance.name)

        # Get simple LLM response without action extraction
        llm_options = build_llm_options_for_conversation(context, session.session_id)
        llm_response = call_llm_with_schema_retry(messages, llm_options, session.session_id)

        @logger.info('✅ Simple response generated without action extraction',
                     tagged: %i[conversation extraction loop_prevention complete],
                     session_id: session.session_id,
                     response_length: llm_response.response_text&.length || 0)

        # Return response with empty tool calls
        [llm_response, []]
      end

      # Build LLM options for conversation-only mode (no tools)
      def build_llm_options_for_conversation(context, _session_id)
        {
          model: context[:model] || GlitchCube.config.default_model, # Use conversation model, not tools model
          temperature: context[:temperature] || GlitchCube.config.conversation&.temperature || 0.8,
          max_tokens: context[:max_tokens] || GlitchCube.config.conversation&.max_tokens || GlitchCube.config.ai.max_tokens,
          timeout: context[:timeout] || GlitchCube.config.conversation&.completion_timeout || 60
          # Explicitly NO tools option - this is pure conversation
        }
      end

      # Format action results into a concise summary
      def format_action_summary(claude_results, extracted_actions)
        if extracted_actions.empty?
          'no actions'
        elsif claude_results[:success]
          action_count = extracted_actions.count
          result_preview = claude_results[:message]&.slice(0, 50) || 'completed'
          "#{action_count} actions executed - #{result_preview}"
        else
          "actions failed - #{claude_results[:message]}"
        end
      end

      # Format action results for appending to conversation (natural, human-friendly)
      def format_action_results_for_conversation(claude_results, extracted_actions)
        if extracted_actions.empty?
          return '' # Don't append anything if no actions
        end

        if claude_results[:success]
          # Extract and clean meaningful result from Claude's response
          result_text = claude_results[:message]&.strip || 'completed successfully'

          # Clean up technical artifacts and make it conversational
          cleaned_result = result_text
                           .gsub(/^Report:\s*[-\s]*/, '')           # Remove "Report:" prefix
                           .gsub(/^[-\s]*/, '')                     # Remove leading dashes
                           .gsub(/\n\s*[-•]\s*/, '; ')              # Convert bullet points to sentences
                           .gsub(/:\s*Successfully/, ' set to')     # "Light: Successfully" -> "Light set to"
                           .gsub(/\bentity_id\b/i, 'device')        # Replace technical terms
                           .strip

          # Limit length to keep TTS natural (max ~50 chars for summary)
          if cleaned_result.length > 60
            # Take first meaningful part and add ellipsis
            summary = cleaned_result.split(/[.;]/).first&.strip || cleaned_result[0..50].strip
            cleaned_result = "#{summary}..."
          end

          # Format naturally with sentinel marker that extractor will ignore
          " Done: #{cleaned_result}."
        else
          # Keep failure messages brief
          error_text = claude_results[:message]&.strip || 'something went wrong'
          brief_error = error_text.length > 30 ? "#{error_text[0..30].strip}..." : error_text
          " Sorry, #{brief_error}."
        end
      end

      # Log complete conversation flow data to conversations.log
      def log_conversation_flow_data(message:, llm_response:, extracted_actions:, claude_results:, session:, persona_instance:, final_response_text: nil)
        # Extract inner thoughts and continue_conversation from parsed content
        parsed_content = llm_response.parsed_content || {}
        inner_thoughts = parsed_content['inner_thoughts'] || parsed_content[:inner_thoughts]
        continue_conversation = parsed_content['continue_conversation'] || parsed_content[:continue_conversation]

        conversation_data = {
          session_id: session.session_id,
          persona: persona_instance.name,
          user_input: message,
          llm_response: llm_response.response_text,
          final_response: final_response_text || llm_response.response_text,
          extracted_actions: extracted_actions,
          claude_response: claude_results[:message],
          tts_output: final_response_text || llm_response.response_text, # Use enhanced response for TTS
          inner_thoughts: inner_thoughts,
          continue_conversation: continue_conversation,
          model: llm_response.model,
          cost: llm_response.cost,
          duration_ms: nil # Will be calculated in the main flow
        }

        @conversation_logger.log_conversation_flow(conversation_data)
      rescue StandardError => e
        @logger.log_error(
          error: e,
          message: 'Failed to log conversation flow data',
          tagged: %i[conversation_logger error]
        )
      end

      # Helper methods for Home Assistant API response format
      def categorize_actions(action_results)
        return [[], []] unless action_results[:claude_results]

        success_actions = []
        failed_actions = []

        # Check if Claude execution was successful overall
        if action_results[:claude_results][:success]
          # Create success entries for each action
          action_results[:actions].each do |action|
            success_actions << {
              name: action,
              result: 'completed'
            }
          end
        else
          # Create failure entries for each action
          action_results[:actions].each do |action|
            failed_actions << {
              name: action,
              result: 'failed',
              reason: action_results[:claude_results][:message] || 'Unknown error'
            }
          end
        end

        [success_actions, failed_actions]
      end

      def build_targets_array(actions)
        return [] unless actions.is_a?(Array)

        actions.map do |action|
          {
            name: action,
            type: 'action_request'
          }
        end
      end

      # 🎭 Generate enhanced persona response incorporating Claude's execution feedback
      def generate_persona_response_with_claude_feedback(persona_instance, original_response, claude_results, extracted_actions, session_id)
        @logger.info('🎭 Generating enhanced persona response with Claude feedback',
                     tagged: %i[conversation persona claude_feedback],
                     session_id: session_id,
                     persona: persona_instance.name,
                     actions_count: extracted_actions.count)

        # Build context for persona to interpret Claude's results
        claude_context = {
          executed_actions: extracted_actions,
          execution_results: claude_results[:message] || 'Actions completed',
          success: claude_results[:success],
          original_intent: original_response
        }

        # Create enhanced prompt for persona to interpret Claude's feedback
        enhanced_prompt = build_claude_feedback_prompt(persona_instance, claude_context)

        begin
          # Call LLM to get persona's interpretation of Claude's results
          enhanced_options = {
            model: GlitchCube.config.default_model,
            temperature: 0.7,
            max_tokens: 200 # Keep it concise for TTS
          }

          enhanced_response = @llm_manager.call_llm(
            messages: [{ role: 'user', content: enhanced_prompt }],
            llm_options: enhanced_options,
            session_id: session_id
          )

          enhanced_text = enhanced_response.response_text&.strip

          if enhanced_text && !enhanced_text.empty?
            @logger.info('✅ Enhanced persona response generated',
                         tagged: %i[conversation persona claude_feedback success],
                         session_id: session_id,
                         original_length: original_response.length,
                         enhanced_length: enhanced_text.length)
            enhanced_text
          else
            @logger.warn('⚠️ Enhanced response was empty, using original',
                         tagged: %i[conversation persona claude_feedback fallback],
                         session_id: session_id)
            original_response
          end
        rescue StandardError => e
          @logger.log_error(error: e,
                            message: 'Failed to generate enhanced persona response',
                            session_id: session_id,
                            persona: persona_instance.name)
          # Fallback to original response
          original_response
        end
      end

      def build_claude_feedback_prompt(persona_instance, claude_context)
        persona_name = persona_instance.name

        <<~PROMPT
          You are #{persona_name}. You just requested some actions and Claude (your tool executor) has completed them.

          YOUR ORIGINAL RESPONSE: "#{claude_context[:original_intent]}"

          ACTIONS YOU REQUESTED: #{claude_context[:executed_actions].join(', ')}

          CLAUDE'S EXECUTION REPORT: "#{claude_context[:execution_results]}"

          SUCCESS: #{claude_context[:success]}

          Now respond as #{persona_name} would, acknowledging what happened and reacting in character.#{' '}
          Keep it conversational and natural - you're speaking to the user, not just reporting results.
          Don't mention Claude directly - just react to the results as if you did it yourself.

          Stay in character as #{persona_name}. Be concise (1-2 sentences) since this will be spoken aloud.
        PROMPT
      end

      # Create enhanced LLM response object with updated response text
      def create_enhanced_llm_response(original_llm_response, enhanced_text)
        # Create a wrapper that preserves all original properties but updates response_text
        enhanced_response = original_llm_response.dup

        # Update the response text while preserving all other attributes
        enhanced_response.define_singleton_method(:response_text) { enhanced_text }

        enhanced_response
      end
    end
  end
end
