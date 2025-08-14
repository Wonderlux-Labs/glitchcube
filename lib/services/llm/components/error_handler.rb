# frozen_string_literal: true

module ::Services
  module Llm
    module Components
      # Centralized error handling for LLM operations
      # Extracted from LLMService to improve maintainability and testability
      class ErrorHandler
        class << self
          def handle_error(error)
            case error
            when ::OpenRouter::ServerError
              handle_openrouter_error(error)
            when Faraday::UnauthorizedError
              raise LLMService::AuthenticationError, 'Invalid OpenRouter API key'
            when Faraday::TooManyRequestsError
              raise LLMService::RateLimitError, 'Rate limit exceeded - please try again later'
            when Faraday::ClientError
              handle_client_error(error)
            else
              # Handle any other error type - error might be a String or other object
              error_message = error.respond_to?(:message) ? error.message : error.to_s
              raise LLMService::LLMError, "Unexpected error: #{error_message}"
            end
          end

          private

          def handle_openrouter_error(error)
            # OpenRouter::ServerError may be raised with just a string message
            error_msg = error.respond_to?(:message) ? error.message : error.to_s

            if error_msg.include?('rate limit')
              raise LLMService::RateLimitError, error_msg
            elsif error_msg.include?('model not found')
              raise LLMService::ModelNotFoundError, error_msg
            else
              raise LLMService::LLMError, "OpenRouter error: #{error_msg}"
            end
          end

          def handle_client_error(error)
            return unless error.response

            status = error.response[:status]
            case status
            when 400
              error_msg = error.respond_to?(:message) ? error.message : error.inspect
              # Check if this looks like a JSON schema error that we could retry without schema
              raise LLMService::JSONSchemaError, "JSON schema not supported (#{status}): #{error_msg}" if error_msg.to_s.downcase.include?('response_format') || error_msg.to_s.downcase.include?('json_schema')

              raise LLMService::LLMError, "Bad request (#{status}): #{error_msg}"

            when 402
              raise LLMService::LLMError, 'Payment required - check your OpenRouter account balance'
            when 404
              raise LLMService::ModelNotFoundError, 'Model not found'
            when 429
              raise LLMService::RateLimitError, 'Rate limit exceeded'
            else
              error_msg = error.respond_to?(:message) ? error.message : error.inspect
              raise LLMService::LLMError, "API error (#{status}): #{error_msg}"
            end
          end
        end
      end
    end
  end
end
