# frozen_string_literal: true

module Services
  class ConversationResponseProcessor
    def initialize(llm_response:, persona_instance:)
      @llm_response = llm_response
      @persona_instance = persona_instance
    end

    def process
      # Use LLMResponse helpers instead of manual JSON parsing
      {
        response: extract_response_text,
        continue_conversation: continue_conversation?,
        inner_thoughts: extract_inner_thoughts,
        cost: @llm_response.cost,
        usage: symbolize_usage(@llm_response.usage),
        model: @llm_response.model,
        raw_response: @llm_response.raw_response
      }.with_indifferent_access
    end

    private

    def extract_response_text
      # Leverage LLMResponse abstraction completely
      text = @llm_response.response_text

      # Handle various response formats
      if text.blank? && @llm_response.parsed_content.is_a?(Hash)
        text = @llm_response.parsed_content['response'] ||
               @llm_response.parsed_content[:response]
      end

      # Only fall back to persona if truly empty
      return text if text.present?

      Services::Logging::SimpleLogger.warn('Empty response from LLM, using persona fallback')
      @persona_instance.generate_fallback_response('I understand.')
    end

    def continue_conversation?
      # Use LLMResponse helper with fallback
      continue = @llm_response.continue_conversation?

      # If nil, check parsed content
      if continue.nil? && @llm_response.parsed_content.is_a?(Hash)
        continue = @llm_response.parsed_content['continue_conversation'] ||
                   @llm_response.parsed_content[:continue_conversation]
      end

      # Default to false if still nil
      continue || false
    end

    def extract_inner_thoughts
      thoughts = @llm_response.inner_thoughts

      # Fallback to parsed content if needed
      if thoughts.blank? && @llm_response.parsed_content.is_a?(Hash)
        thoughts = @llm_response.parsed_content['inner_thoughts'] ||
                   @llm_response.parsed_content[:inner_thoughts]
      end

      thoughts || ''
    end

    def symbolize_usage(usage)
      return usage if usage.nil?
      return usage if usage.is_a?(Hash) && usage.keys.all? { |k| k.is_a?(Symbol) }

      usage.transform_keys(&:to_sym)
    end
  end
end
