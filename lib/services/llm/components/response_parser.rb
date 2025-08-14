# frozen_string_literal: true

require 'active_support/core_ext/hash/indifferent_access'

module Services
  module Llm
    class ResponseParser
      class << self
        def parse(response, model, options = {})
          # Convert response to HashWithIndifferentAccess for consistent access
          indifferent_response = ensure_indifferent_access(response)

          response_model = indifferent_response[:model] || model
          LLMResponse.new(
            raw_response: indifferent_response,
            model: response_model,
            content: extract_content(indifferent_response),
            usage: extract_usage(indifferent_response),
            tool_calls: extract_tool_calls(indifferent_response),
            expects_json: options[:response_format].present?
          )
        end

        private

        def extract_content(response)
          return response if response.is_a?(String)

          # Response is already indifferent from parse method
          response.dig(:choices, 0, :message, :content) || response[:content] || ''
        end

        def extract_usage(response)
          return default_usage if response.is_a?(String)

          # Response is already indifferent from parse method
          usage = response[:usage] || {}
          usage = usage.with_indifferent_access if usage.is_a?(Hash)

          {
            prompt_tokens: usage[:prompt_tokens] || 0,
            completion_tokens: usage[:completion_tokens] || 0,
            total_tokens: usage[:total_tokens] || 0
          }
        end

        def extract_tool_calls(response)
          return nil if response.is_a?(String)

          # Response is already indifferent from parse method
          choice = response.dig(:choices, 0)
          return nil unless choice.is_a?(Hash)

          message = choice[:message]
          return nil unless message

          tool_calls = message[:tool_calls]
          return nil unless tool_calls.is_a?(Array)

          tool_calls.filter_map do |tool_call|
            tool_call = tool_call.with_indifferent_access if tool_call.is_a?(Hash)
            func = tool_call[:function]
            next unless func

            func = func.with_indifferent_access if func.is_a?(Hash)

            {
              id: tool_call[:id],
              type: tool_call[:type] || 'function',
              function: {
                name: func[:name],
                arguments: func[:arguments]
              }
            }
          end
        end

        def ensure_indifferent_access(response)
          case response
          when Hash
            response.with_indifferent_access
          when String
            begin
              JSON.parse(response).with_indifferent_access
            rescue JSON::ParserError
              # Return an empty indifferent hash for invalid JSON
              {}.with_indifferent_access
            end
          else
            # For any other type, wrap in a hash
            { content: response.to_s }.with_indifferent_access
          end
        rescue StandardError => e
          Rails.logger.error "Failed to convert response: #{e.message}" if defined?(Rails)
          {}.with_indifferent_access
        end

        def default_usage
          { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 }
        end
      end
    end
  end
end
