# frozen_string_literal: true

module Services
  module Conversation
    class LLMInteractionManager
      def initialize(logger: Services::Logging::SimpleLogger)
        @logger = logger
      end

      def prepare_messages(conversation_history, system_prompt, user_message)
        messages = [
          { role: 'system', content: system_prompt }
        ]
        messages.concat(conversation_history)
        messages << { role: 'user', content: user_message }
        messages
      end

      def call_llm(messages:, llm_options: {}, session_id: nil)
        @logger.info('Calling LLM', tagged: %i[conversation llm], session_id: session_id, model: llm_options[:model], message_count: messages.length)
        start_time = Time.now

        response = Services::LLMService.complete_with_messages(
          messages: messages,
          **llm_options
        )

        duration_ms = ((Time.now - start_time) * 1000).round
        @logger.info("LLM call finished in #{duration_ms}ms", tagged: %i[conversation llm], session_id: session_id, model: response.model, prompt_tokens: response.usage[:prompt_tokens], completion_tokens: response.usage[:completion_tokens], cost: response.cost, duration_ms: duration_ms)

        response
      end

      def build_system_prompt(persona_instance, context)
        enriched_context = context.merge(
          current_persona: persona_instance.name,
          session_id: context[:session_id] || SecureRandom.uuid,
          interaction_count: context[:interaction_count] || 1,
          response_format: context[:response_format] || !get_response_schema(context).nil?
        )

        base_prompt = persona_instance.generate_system_prompt
        final_prompt = Services::ContextInjectionService.inject_context(base_prompt, enriched_context)

        unless context[:tools].present? && !context[:tools].empty?
          json_instruction = "\n\nIMPORTANT: Your response MUST be valid JSON in this exact format:\n" \
                             '{"response": "your complete message here", "continue_conversation": true/false, "inner_thoughts": "optional internal thoughts"}'
          final_prompt += json_instruction
        end

        @logger.debug('System prompt generated', tagged: %i[conversation prompt], char_count: final_prompt.length, session_id: context[:session_id])
        final_prompt
      end

      def select_appropriate_model(context, session_id)
        model = if context[:tools].present? && !context[:tools].empty?
                  context[:tools_model] || GlitchCube.config.ai.default_tools_model
                else
                  context[:model] || GlitchCube.config.ai.default_model
                end
        @logger.debug("Selected model: #{model}", tagged: %i[conversation llm], session_id: session_id, reason: context[:tools].present? ? 'tools' : 'default')
        model
      end

      def get_response_schema(context)
        return nil unless defined?(GlitchCube::Schemas::ConversationResponseSchema)

        if context[:image_analysis]
          GlitchCube::Schemas::ConversationResponseSchema.image_analysis_response
        elsif context[:tools]
          GlitchCube::Schemas::ConversationResponseSchema.tool_response
        else
          GlitchCube::Schemas::ConversationResponseSchema.simple_response
        end
      end
    end
  end
end
