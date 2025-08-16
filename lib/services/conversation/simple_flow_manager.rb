# frozen_string_literal: true

require 'securerandom'
require_relative '../../modules/globals'

module Services
  module Conversation
    class SimpleFlowManager
      include Modules::ErrorHandling

      def initialize
        @logger = $logger
        @llm_manager = LlmInteractionManager.new
        @history_manager = HistoryManager.new
        @state_manager = StateManager.new
        @response_processor = ResponseProcessor.new
      end

      def process_conversation(message:, context:, persona:)
        start_time = Time.now

        # Get or create session
        session = get_or_create_session(context)
        persona_instance = get_persona

        # Update conversation persona if it changed (the "glitch" feature)
        if session.conversation.persona != persona_instance.name
          @logger.info('🎭 Persona switching mid-conversation!',
                       tagged: %i[conversation persona_switch],
                       session_id: session.session_id,
                       old_persona: session.conversation.persona,
                       new_persona: persona_instance.name)
          session.conversation.update!(persona: persona_instance.name)
        end

        @logger.info('🚀 Starting simple conversation flow',
                     tagged: %i[conversation simple_flow start],
                     session_id: session.session_id,
                     persona: persona_instance.name)

        # Record user message
        @state_manager.record_message(
          session: session,
          role: 'user',
          content: message,
          persona: persona_instance.name
        )

        # Single LLM call
        llm_response = call_llm(message, session, persona_instance, context)

        # Extract actions and continue_conversation flag
        action_extractor = ActionExtractor.new(logger: @logger)
        parsed_content = llm_response.parsed_content || {}
        extracted_actions = action_extractor.extract_actions_only(
          parsed_content,
          session.session_id
        )

        # Get continue_conversation from LLM response (with safe navigation)
        continue_conversation = if parsed_content.is_a?(Hash)
                                  parsed_content['continue_conversation'] ||
                                    parsed_content[:continue_conversation] ||
                                    false
                                else
                                  false
                                end

        # Record assistant response with error handling
        begin
          # Sanitize metadata to ensure JSON serialization
          safe_metadata = {
            actions: extracted_actions.is_a?(Array) ? extracted_actions.map(&:to_s) : [],
            continue_conversation: continue_conversation,
            inner_thoughts: parsed_content.is_a?(Hash) ?
                          (parsed_content['inner_thoughts'] || parsed_content[:inner_thoughts])&.to_s : nil
          }

          @logger.debug('💾 Recording assistant message with metadata',
                        tagged: %i[conversation simple_flow record_debug],
                        session_id: session.session_id,
                        actions_count: safe_metadata[:actions].count,
                        actions_sample: safe_metadata[:actions].first(3),
                        continue_conversation: safe_metadata[:continue_conversation],
                        inner_thoughts_length: safe_metadata[:inner_thoughts]&.length)

          @state_manager.record_message(
            session: session,
            role: 'assistant',
            content: llm_response.response_text,
            persona: persona_instance.name,
            model_used: llm_response.model,
            prompt_tokens: llm_response.usage[:prompt_tokens],
            completion_tokens: llm_response.usage[:completion_tokens],
            cost: llm_response.cost,
            response_time_ms: ((Time.now - start_time) * 1000).round,
            metadata: safe_metadata
          )
        rescue StandardError => e
          @logger.error('💥 Failed to record assistant message',
                        tagged: %i[conversation simple_flow record_error],
                        session_id: session.session_id,
                        error: e.message,
                        parsed_content_class: parsed_content.class,
                        backtrace: e.backtrace.first(3))
          raise e
        end

        @logger.info('🔍 Reached actions section successfully',
                     tagged: %i[conversation simple_flow debug],
                     session_id: session.session_id,
                     extracted_actions_count: extracted_actions.count)

        # Execute actions via Claude
        if extracted_actions.any?
          @logger.info('📋 Actions extracted - sending to Claude',
                       tagged: %i[conversation simple_flow actions_extracted],
                       session_id: session.session_id,
                       action_count: extracted_actions.count,
                       actions: extracted_actions)

          fire_background_tools(extracted_actions, session, message)
        end

        # Return immediate response for HA
        response = build_response(llm_response, session, persona_instance.name, extracted_actions, continue_conversation)

        total_duration = ((Time.now - start_time) * 1000).round
        @logger.info('✅ Simple conversation flow completed',
                     tagged: %i[conversation simple_flow complete],
                     session_id: session.session_id,
                     duration_ms: total_duration,
                     action_count: extracted_actions.count,
                     continue_conversation: continue_conversation)

        response
      end

      private

      def get_or_create_session(context)
        session_id = context[:session_id] || "voice_#{SecureRandom.uuid}"
        @state_manager.create_or_get_session(session_id, context)
      end

      def get_persona
        Personas::PersonaFactory.create(Modules::Globals.persona)
      end

      def call_llm(message, session, persona_instance, context)
        # Build messages
        system_prompt = @llm_manager.build_system_prompt(persona_instance, context)
        history = @history_manager.get_conversation_context(session, limit: 5)
        messages = @llm_manager.prepare_messages(history, system_prompt, message)

        # Build LLM options
        llm_options = {
          model: context[:model] || GlitchCube.config.default_model,
          temperature: context[:temperature] || 0.8,
          max_tokens: context[:max_tokens] || GlitchCube.config.ai.max_tokens || 2000,
          timeout: context[:timeout] || GlitchCube.config.conversation&.completion_timeout || 60
        }

        # Call LLM with retry logic
        @llm_manager.call_llm(
          messages: messages,
          llm_options: llm_options,
          session_id: session.session_id
        )
      end

      def fire_background_tools(actions, session, original_message)
        @logger.info('📋 Queuing background tool execution',
                     tagged: %i[conversation simple_flow background_tools],
                     session_id: session.session_id,
                     action_count: actions.count,
                     actions: actions)

        begin
          # Use Sidekiq for production-safe background execution
          Jobs::ToolExecutionWorker.perform_async(
            actions,
            session.session_id,
            original_message
          )

          @logger.info('✅ Background tool execution queued successfully',
                       tagged: %i[conversation simple_flow tools_queued],
                       session_id: session.session_id)
        rescue StandardError => e
          @logger.error('💥 Failed to queue background tool execution',
                        tagged: %i[conversation simple_flow queue_error],
                        session_id: session.session_id,
                        error: e.message)
          # Continue without tools rather than failing the entire conversation
        end
      end

      def build_response(llm_response, session, persona_name, actions, continue_conversation)
        # Check if we've hit the 12 message limit (6 rounds)
        if session.conversation.message_count >= 12
          continue_conversation = false
          @logger.info('🔚 Conversation ending due to message limit',
                       tagged: %i[conversation simple_flow message_limit],
                       session_id: session.session_id,
                       message_count: session.conversation.message_count)
        end

        {
          response: llm_response.response_text,
          continue_conversation: continue_conversation,  # From LLM response or message limit override
          end_conversation: !continue_conversation,      # Inverse for HA
          session_id: session.session_id,
          persona: persona_name,
          action_count: actions.count,
          timestamp: Time.now.iso8601
        }
      end

      # Check for previous tool failures and inject context
      def check_previous_tool_failures(session_id)
        redis = Redis.new(url: GlitchCube.config.redis_url)
        failure_message = redis.get("tool_failure:#{session_id}")

        if failure_message
          redis.del("tool_failure:#{session_id}") # Clear it
          @logger.info('📋 Found previous tool failure to inject',
                       tagged: %i[conversation simple_flow tool_failure],
                       session_id: session_id,
                       failure: failure_message[0..50])

          "SYSTEM: Previous action failed - #{failure_message}"
        end
      rescue StandardError => e
        @logger.warn('⚠️ Could not check for tool failures',
                     tagged: %i[conversation simple_flow redis_error],
                     session_id: session_id,
                     error: e.message)
        nil
      end
    end
  end
end
