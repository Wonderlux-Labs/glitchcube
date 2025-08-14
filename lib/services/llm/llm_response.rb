# frozen_string_literal: true

require 'active_support/core_ext/hash/indifferent_access'

module Services
  module Llm
    # The Response class represents the response received from the OpenRouter/LLM API.
    # It provides convenience methods to access structured outputs, tool calls, and parsed JSON responses.
    class LLMResponse
      attr_reader :raw_response, :model, :usage, :expects_json

      # Initializes a new instance of the LLMResponse class.
      #
      # @param response [Hash] The response from the LLM service
      def initialize(response)
        # Convert to HashWithIndifferentAccess for consistent access
        response = response.with_indifferent_access if response.is_a?(Hash)

        @raw_response = (response[:raw_response] || response).with_indifferent_access
        @model = response[:model]
        @usage = response[:usage] || extract_usage
        @content = response[:content] || extract_content
        @tool_calls = response[:tool_calls]
        @expects_json = response[:expects_json] || false
      end

      # Returns the main content/text from the response
      #
      # @return [String] The response content
      attr_reader :content

      alias text content
      alias message content

      # Returns the chat completion choices from the response
      #
      # @return [Array] An array of completion choices
      def choices
        # Convert each choice to indifferent hash for consistent access
        @choices ||= (@raw_response[:choices] || []).map do |choice|
          choice.respond_to?(:with_indifferent_access) ? choice.with_indifferent_access : choice
        end
      end

      # Returns the first choice from completions
      #
      # @return [Hash, nil] The first choice or nil
      def choice
        choices.first
      end

      # Returns the message from the first choice
      #
      # @return [Hash, nil] The message or nil
      def message_data
        # choice is already an indifferent hash from our choices method
        choice&.[](:message)
      end

      # Returns tool calls from the response
      #
      # @return [Array, nil] Tool calls or nil if not found
      def tool_calls
        # Convert tool calls to indifferent hashes for consistent access
        @tool_calls ||= (message_data&.[](:tool_calls) || []).map do |tc|
          tc.respond_to?(:with_indifferent_access) ? tc.with_indifferent_access : tc
        end
      end

      # Returns function calls from tool calls
      #
      # @return [Array, nil] An array of function calls or nil
      def function_calls
        tool_calls&.map { |tool_call| tool_call[:function] }
      end

      # Returns the first function call
      #
      # @return [Hash, nil] The first function call or nil
      def function_call
        function_calls&.first
      end

      # Checks if there is only a single function call
      #
      # @return [Boolean] True if single function call
      def single_function_call?
        function_calls&.size == 1
      end

      # Checks if response contains tool calls
      #
      # @return [Boolean] True if has tool calls
      def tool_calls?
        !tool_calls.nil? && !tool_calls.empty?
      end

      alias has_tool_calls? tool_calls?

      # Parse the content as JSON (for structured outputs)
      #
      # @return [Hash, nil] Parsed JSON or nil if not valid JSON
      def parsed_content
        @parsed_content ||= parse_json_content
      end

      alias json parsed_content
      alias structured_output parsed_content

      # Parse function arguments for all function calls
      #
      # @return [Array, Hash] Parsed arguments for function(s)
      def parse_function_arguments
        return nil unless function_calls

        if single_function_call?
          parse_json_safely(function_call[:arguments])
        else
          function_calls.map do |func|
            {
              name: func[:name],
              arguments: parse_json_safely(func[:arguments])
            }
          end
        end
      end

      # Get function arguments by function name
      #
      # @param function_name [String] The function name
      # @return [Hash, nil] The parsed arguments or nil
      def function_arguments_for(function_name)
        func = function_calls&.find do |f|
          f[:name] == function_name
        end
        return nil unless func

        parse_json_safely(func[:arguments])
      end

      # For conversation responses - check if should continue
      #
      # @return [Boolean] Whether to continue conversation, defaults to false
      def continue_conversation?
        if parsed_content.is_a?(Hash) && parsed_content.key?(:continue_conversation)
          # Check for the continue_conversation field in parsed JSON and coerce to a strict boolean
          [true, 'true', 1, '1'].include?(parsed_content[:continue_conversation])
        else
          parsed_content.nil? && content.present?
        end
      end

      # Get the main response text (handles structured and unstructured)
      #
      # @return [String] The response text
      def response_text
        if parsed_content.is_a?(Hash)
          # Try to extract the actual response text from structured output
          # Use standard 'response' field, fall back to 'text' for compatibility
          text = parsed_content[:response] ||
                 parsed_content[:text]

          # Return the text if found (even if empty string)
          return text unless text.nil?

          # No text field found in structured response
          # Return nil to indicate no textual response available
          # This prevents raw JSON from being passed as response text
          if defined?(Logging::SimpleLogger)
            Logging::SimpleLogger.debug('No response/text field in structured output',
                                        tagged: %i[llm_response structured],
                                        parsed_keys: parsed_content.keys)
          end
          return nil
        end

        # Non-JSON content is likely plain text response - return as-is
        content
      end

      # Define structured output accessor methods using metaprogramming
      STRUCTURED_OUTPUT_KEYS = {
        ha_actions: :actions,
        lighting: :lighting,
        # inner_thoughts handled explicitly below for better control
        memory_note: :memory_note,
        request_action: :request_action,
        proactive_behaviors: :proactive_behaviors
      }.freeze

      STRUCTURED_OUTPUT_KEYS.each do |method_name, key|
        define_method(method_name) do
          return nil unless parsed_content.is_a?(Hash)

          parsed_content[key]
        end
      end

      # Explicit inner_thoughts method with intelligent handling for both JSON and plain text
      #
      # @return [String] The inner thoughts or a default message
      def inner_thoughts
        if parsed_content.is_a?(Hash) && parsed_content.key?(:inner_thoughts)
          return parsed_content[:inner_thoughts].to_s
        end

        # Provide a default thought for plain text responses for better debugging
        return 'Response was plain text, not JSON.' if parsed_content.nil? && content.present?

        '' # Default empty string
      end

      # Calculate cost for this response
      #
      # @return [Float] The cost in dollars
      def cost
        return 0.0 unless @usage && @model

        # Use ModelPricing if available
        if defined?(ModelPricing)
          ModelPricing.calculate_cost(
            @model,
            @usage[:prompt_tokens] || 0,
            @usage[:completion_tokens] || 0
          )
        else
          0.0
        end
      end

      # Check if this was an error response
      #
      # @return [Boolean] True if error
      def error?
        @raw_response.key?(:error)
      end

      # Get error message if present
      #
      # @return [String, nil] Error message or nil
      def error_message
        @raw_response[:error]
      end

      private

      def extract_content
        if choices.any?
          msg = choice&.[](:message)
          msg&.[](:content) || ''
        else
          @raw_response[:content] || ''
        end
      end

      def extract_usage
        usage_data = @raw_response[:usage] || {}
        usage_data = usage_data.with_indifferent_access if usage_data.is_a?(Hash)
        {
          prompt_tokens: usage_data[:prompt_tokens] || 0,
          completion_tokens: usage_data[:completion_tokens] || 0,
          total_tokens: usage_data[:total_tokens] || 0
        }
      end

      def parse_json_content
        return nil unless @content.is_a?(String)

        # Clean content - handle markdown JSON blocks
        cleaned = @content.strip
        cleaned = cleaned.gsub(/^```json\s*/, '').gsub(/\s*```$/, '') if cleaned.include?('```')

        # Only try to parse if it looks like JSON
        return nil unless cleaned.start_with?('{') || cleaned.start_with?('[')

        # Parse and convert to indifferent hash
        result = parse_json_safely(cleaned)
        result.is_a?(Hash) ? result.with_indifferent_access : result
      end

      def parse_json_safely(str)
        return nil unless str

        str = str.to_s unless str.is_a?(String)
        JSON.parse(str)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
