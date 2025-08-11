# frozen_string_literal: true

module Services
  # The Response class represents the response received from the OpenRouter/LLM API.
  # It provides convenience methods to access structured outputs, tool calls, and parsed JSON responses.
  class LLMResponse
    attr_reader :raw_response, :model, :usage, :expects_json

    # Initializes a new instance of the LLMResponse class.
    #
    # @param response [Hash] The response from the LLM service
    def initialize(response)
      @raw_response = response[:raw_response] || response
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
      @raw_response['choices'] || @raw_response[:choices] || []
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
      choice&.dig('message') || choice&.dig(:message)
    end

    # Returns tool calls from the response
    #
    # @return [Array, nil] Tool calls or nil if not found
    def tool_calls
      @tool_calls ||= message_data&.dig('tool_calls') || message_data&.dig(:tool_calls)
    end

    # Returns function calls from tool calls
    #
    # @return [Array, nil] An array of function calls or nil
    def function_calls
      tool_calls&.map { |tool_call| tool_call['function'] || tool_call[:function] }
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
        parse_json_safely(function_call['arguments'] || function_call[:arguments])
      else
        function_calls.map do |func|
          {
            name: func['name'] || func[:name],
            arguments: parse_json_safely(func['arguments'] || func[:arguments])
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
        (f['name'] || f[:name]) == function_name
      end
      return nil unless func

      parse_json_safely(func['arguments'] || func[:arguments])
    end

    # For conversation responses - check if should continue
    #
    # @return [Boolean, nil] Whether to continue conversation, or nil if not specified
    def continue_conversation?
      if parsed_content.is_a?(Hash)
        # Explicit value if present
        return parsed_content['continue_conversation'] if parsed_content.key?('continue_conversation')
        return parsed_content[:continue_conversation] if parsed_content.key?(:continue_conversation)
      end

      # Fallback: try to extract from response text if it looks like JSON
      if content&.include?('"continue_conversation"')
        match = content.match(/"continue_conversation"\s*:\s*(true|false)/)
        return match[1] == 'true' if match
      end

      # Return nil when not specified, let ConversationModule decide the safe default
      false
    end

    # Get the main response text (handles structured and unstructured)
    #
    # @return [String] The response text
    def response_text
      if parsed_content.is_a?(Hash)
        # Try to extract the actual response text from structured output
        text = parsed_content['response'] || parsed_content[:response] ||
               parsed_content['text'] || parsed_content[:text]

        # Return the text if found (even if empty string)
        return text unless text.nil?

        # No text field found in structured response
        # Return nil to indicate no textual response available
        # This prevents raw JSON from being passed as response text
        if defined?(Services::SimpleLogger)
          Services::SimpleLogger.debug('No response/text field in structured output',
                                       tagged: %i[llm_response structured],
                                       parsed_keys: parsed_content.keys)
        end
        return nil
      end

      # Non-JSON content is likely plain text response - return as-is
      content
    end

    # Extract any Home Assistant actions from structured response
    #
    # @return [Array, nil] Array of HA actions or nil
    def ha_actions
      return nil unless parsed_content.is_a?(Hash)

      parsed_content['actions'] || parsed_content[:actions]
    end

    # Extract lighting instructions from structured response
    #
    # @return [Hash, nil] Lighting configuration or nil
    def lighting
      return nil unless parsed_content.is_a?(Hash)

      parsed_content['lighting'] || parsed_content[:lighting]
    end

    # Extract inner thoughts from structured response
    #
    # @return [String, nil] Inner thoughts or nil
    def inner_thoughts
      return nil unless parsed_content.is_a?(Hash)

      parsed_content['inner_thoughts'] || parsed_content[:inner_thoughts]
    end

    # Extract memory note from structured response
    #
    # @return [String, nil] Memory note or nil
    def memory_note
      return nil unless parsed_content.is_a?(Hash)

      parsed_content['memory_note'] || parsed_content[:memory_note]
    end

    # Extract request action from structured response
    #
    # @return [Hash, nil] Request action or nil
    def request_action
      return nil unless parsed_content.is_a?(Hash)

      parsed_content['request_action'] || parsed_content[:request_action]
    end

    # Calculate cost for this response
    #
    # @return [Float] The cost in dollars
    def cost
      return 0.0 unless @usage && @model

      # Use ModelPricing if available
      if defined?(GlitchCube::ModelPricing)
        GlitchCube::ModelPricing.calculate_cost(
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
      @raw_response.key?(:error) || @raw_response.key?('error')
    end

    # Get error message if present
    #
    # @return [String, nil] Error message or nil
    def error_message
      @raw_response[:error] || @raw_response['error']
    end

    private

    def extract_content
      if choices.any?
        msg = choice&.dig('message') || choice&.dig(:message)
        msg&.dig('content') || msg&.dig(:content) || ''
      else
        @raw_response[:content] || @raw_response['content'] || ''
      end
    end

    def extract_usage
      usage_data = @raw_response[:usage] || @raw_response['usage'] || {}
      {
        prompt_tokens: usage_data[:prompt_tokens] || usage_data['prompt_tokens'] || 0,
        completion_tokens: usage_data[:completion_tokens] || usage_data['completion_tokens'] || 0,
        total_tokens: usage_data[:total_tokens] || usage_data['total_tokens'] || 0
      }
    end

    def parse_json_content
      return nil unless @content.is_a?(String)

      # Clean content - handle markdown JSON blocks
      cleaned = @content.strip
      cleaned = cleaned.gsub(/^```json\s*/, '').gsub(/\s*```$/, '') if cleaned.include?('```')

      # Only try to parse if it looks like JSON or we're expecting JSON
      return nil unless @expects_json || cleaned.start_with?('{') || cleaned.start_with?('[')

      result = parse_json_safely(cleaned)

      # If we expect JSON but failed to parse, try to recover it
      if result.nil? && @expects_json && cleaned.length.positive?
        result = recover_json(cleaned)
      end

      result
    end

    def parse_json_safely(str)
      return nil unless str

      str = str.to_s unless str.is_a?(String)
      JSON.parse(str)
    rescue JSON::ParserError
      nil
    end

    # Attempt to recover malformed JSON using a small LLM
    # Only used when we explicitly expect JSON but parsing failed
    def recover_json(malformed_json)
      return nil unless defined?(Services::LLMService)

      if defined?(Services::SimpleLogger)
        Services::SimpleLogger.warn('Attempting JSON recovery with LLM',
                                    tagged: %i[llm_response json_recovery],
                                    content_preview: malformed_json[0..200])
      end

      begin
        # Use a small, fast model to fix the JSON
        recovery_prompt = <<~PROMPT
          Fix this malformed JSON and return ONLY valid JSON, no explanation:

          #{malformed_json}

          Return ONLY the corrected JSON object/array with no additional text.
        PROMPT

        recovery_response = Services::LLMService.complete(
          system_prompt: 'You are a JSON fixer. Return only valid JSON with no explanation.',
          user_message: recovery_prompt,
          model: 'meta-llama/llama-3.2-3b-instruct',  # Ultra cheap model ($0.01/1M)
          temperature: 0,
          max_tokens: 4000
        )

        recovered_content = if recovery_response.is_a?(Services::LLMResponse)
                              recovery_response.content
                            else
                              recovery_response[:content] || recovery_response['content']
                            end

        # Clean any markdown or extra text
        recovered_content = recovered_content.strip
        recovered_content = recovered_content.gsub(/^```json\s*/, '').gsub(/\s*```$/, '') if recovered_content.include?('```')

        # Try to parse the recovered JSON
        recovered = JSON.parse(recovered_content)

        if defined?(Services::SimpleLogger)
          Services::SimpleLogger.info('Successfully recovered JSON',
                                      tagged: %i[llm_response json_recovery],
                                      keys: recovered.keys)
        end

        recovered
      rescue StandardError => e
        if defined?(Services::SimpleLogger)
          Services::SimpleLogger.error('JSON recovery failed',
                                       tagged: %i[llm_response json_recovery],
                                       error: e.message)
        end
        nil
      end
    end
  end
end
