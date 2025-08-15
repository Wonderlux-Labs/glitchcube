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

        # Only generate fallback if response is empty AND no tool calls are present
        if (response_text.nil? || response_text.strip.empty?) && !llm_response.tool_calls?
          @logger.error('Response validation failed - empty response with no tool calls. Generating fallback.',
                        tagged: %i[conversation validation error],
                        session_id: session_id,
                        llm_content: llm_response.content,
                        llm_parsed: llm_response.parsed_content,
                        llm_raw_choices: llm_response.raw_response&.dig('choices'),
                        model: llm_response.model)
          response_text = persona_instance.generate_fallback_response('I understand.')
          # Fallback responses should end conversations as a safe default
          continue_conversation = false
        elsif (response_text.nil? || response_text.strip.empty?) && llm_response.tool_calls?
          # If we have tool calls but no response text, that's fine - tool execution will provide the interaction
          @logger.debug('Response has tool calls but no text - this is expected for tool-only responses',
                        tagged: %i[conversation validation],
                        session_id: session_id,
                        tool_call_count: llm_response.tool_calls.count)
          response_text = '' # Ensure we have a string for processing
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
