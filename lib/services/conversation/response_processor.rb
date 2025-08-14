# frozen_string_literal: true

module Services
  module Conversation
    class ResponseProcessor
      def initialize(logger: Logging::SimpleLogger)
        @logger = logger
      end

      def process_response(llm_response, persona_instance, session_id)
        @logger.info('Processing LLM response', tagged: %i[conversation response], session_id: session_id, model: llm_response.model)

        response_text = llm_response.response_text
        continue_conversation = llm_response.continue_conversation?
        inner_thoughts = llm_response.inner_thoughts

        response_text = response_text.to_s unless response_text.nil?

        if response_text.nil? || response_text.strip.empty?
          @logger.error('Response validation failed - empty response. Generating fallback.',
                        tagged: %i[conversation validation error],
                        session_id: session_id,
                        llm_content: llm_response.content,
                        llm_parsed: llm_response.parsed_content,
                        llm_raw_choices: llm_response.raw_response&.dig('choices'),
                        model: llm_response.model)
          response_text = persona_instance.generate_fallback_response('I understand.')
        end

        processed_response = {
          response: response_text,
          continue_conversation: continue_conversation,
          inner_thoughts: inner_thoughts
        }.with_indifferent_access

        @logger.info('Finished processing LLM response', tagged: %i[conversation response], session_id: session_id, response_length: response_text.length, continue: continue_conversation)
        processed_response
      end
    end
  end
end
