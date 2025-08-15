# frozen_string_literal: true

module Services
  module Llm
    module Components
      # Centralized error handling for LLM operations
      # Extracted from LLMService to improve maintainability and testability
      class ErrorHandler
        class << self
          def handle_error(error)
            # DUMP EVERYTHING for debugging before specific handling
            debug_handle_error(error)

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

          def debug_handle_error(error)
            # JUST DUMP EVERYTHING - no fancy parsing, no special cases
            error_info = []
            error_info << "Error class: #{error.class}"
            error_info << "Error message: #{error.message}" if error.respond_to?(:message)

            # Get the actual API response if it exists
            if error.respond_to?(:response) && error.response && error.response[:body]
              error_info << "API Response: #{error.response[:body]}"
            end

            # Dump the whole error object as backup
            error_info << "Full error: #{error.inspect}"

            # Log to debug level so we always see it
            ::Services::Logging::SimpleLogger.debug(
              'RAW ERROR DUMP',
              tagged: %i[llm error_debug],
              raw_error_info: error_info.join(' | ')
            )
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

            # LOG THE FULL ERROR RESPONSE BODY - this would have saved hours of debugging!
            if error.response[:body]
              ::Services::Logging::SimpleLogger.error(
                'LLM API ERROR RESPONSE BODY',
                tagged: %i[llm error_response],
                status: status,
                response_body: error.response[:body]
              )
            end

            case status
            when 400
              if error.response && error.response[:body]
                begin
                  error_body = JSON.parse(error.response[:body])
                  api_error_msg = error_body.dig('error', 'message') || error_body['message']
                  if api_error_msg
                    # Check if this looks like a JSON schema error that we could retry without schema
                    raise LLMService::JSONSchemaError, "JSON schema not supported (#{status}): #{api_error_msg}" if api_error_msg.to_s.downcase.include?('response_format') || api_error_msg.to_s.downcase.include?('json_schema')

                    raise LLMService::LLMError, "Bad request (#{status}): #{api_error_msg}"
                  end
                rescue JSON::ParserError
                  # Fall back to error.inspect if JSON parsing fails
                  error_msg = error.inspect
                  raise LLMService::LLMError, "Bad request (#{status}): #{error_msg}"
                end
              end

              # Final fallback
              error_msg = error.respond_to?(:message) ? error.message : error.inspect
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
