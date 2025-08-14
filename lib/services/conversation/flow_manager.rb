# frozen_string_literal: true

require 'securerandom'

module Services
  module Conversation
    class FlowManager
      def initialize(error_handler: Services::Conversation::ErrorHandler, logger: Services::Logging::SimpleLogger)
        @state_manager = Services::Conversation::StateManager.new
        @history_manager = Services::Conversation::HistoryManager.new
        @llm_manager = Services::Conversation::LlmInteractionManager.new(logger: logger)
        @tool_engine = Services::Conversation::ToolExecutionEngine.new(logger: logger)
        @response_processor = Services::Conversation::ResponseProcessor.new(logger: logger)
        @error_handler = error_handler
        @logger = logger
      end

      def process_conversation(message:, context: {}, persona: nil)
        start_time = Time.now
        persona_name = persona || context[:persona] || Services::PersonaStateService.get_current_persona
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
        context = Services::Memory::ContextEnrichmentService.enrich(context)
        system_prompt = @llm_manager.build_system_prompt(persona_instance, context)
        conversation_history = @history_manager.get_conversation_context(session)

        messages = @llm_manager.prepare_messages(conversation_history, system_prompt, message)
        @state_manager.record_message(session: session, role: 'user', content: message, persona: persona_instance.name)

        llm_options = build_llm_options(context, session.session_id)
        llm_response = @llm_manager.call_llm(messages: messages, llm_options: llm_options, session_id: session.session_id)

        last_tool_calls = []
        if llm_response.tool_calls?
          @logger.info('LLM response includes tool calls. Executing tools.', tagged: %i[conversation tools], session_id: session.session_id, tool_call_count: llm_response.tool_calls.count)
          tool_execution_result = @tool_engine.execute_tool_calls(llm_response, session.session_id)
          tool_results = tool_execution_result[:tool_results]
          last_tool_calls = tool_execution_result[:last_tool_calls]

          messages << llm_response.message_data
          messages.concat(tool_results)

          @logger.info('Making follow-up LLM call with tool results.', tagged: %i[conversation tools], session_id: session.session_id)
          llm_response = @llm_manager.call_llm(messages: messages, llm_options: build_llm_options(context, session.session_id, with_tools: false), session_id: session.session_id)
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
        elsif (response_schema = @llm_manager.get_response_schema(context))
          options[:response_format] = GlitchCube::Schemas::ConversationResponseSchema.to_openrouter_format(response_schema)
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
    end
  end
end
