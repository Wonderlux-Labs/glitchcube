# frozen_string_literal: true

module Services
  module Llm
    # Centralized retry handling for LLM operations
    # Extracted from LLMService to improve maintainability and testability
    class RetryHandler
      class << self
        def with_retry_logic(model:, max_attempts: 3)
          # Disable retries when disabled in config
          max_attempts = 1 unless GlitchCube.config.enable_retries

          attempt = 0
          delay = 1.0
          last_error = nil

          begin
            attempt += 1
            if attempt > 1
              Services::Logging::SimpleLogger.info(
                "LLM API retry attempt #{attempt}/#{max_attempts}",
                tagged: %i[llm retry],
                attempt: attempt,
                max_attempts: max_attempts,
                model: model
              )
            end

            result = yield

            if attempt > 1
              Services::Logging::SimpleLogger.info(
                'LLM API call succeeded on retry',
                tagged: %i[llm retry success],
                attempt: attempt
              )
            end
            return result
          rescue LLMService::RateLimitError => e
            last_error = e
            if attempt < max_attempts
              # Longer wait for rate limits
              wait_time = delay * 2
              Services::Logging::SimpleLogger.warn(
                'Rate limited - waiting before retry',
                tagged: %i[llm rate_limit],
                wait_time_seconds: wait_time
              )
              sleep(wait_time)
              delay *= 2
              retry
            end
          rescue LLMService::AuthenticationError => e
            # Never retry authentication errors
            last_error = e
            Services::Logging::SimpleLogger.error(
              'Authentication failed - not retrying',
              tagged: %i[llm auth error]
            )
          rescue LLMService::LLMError => e
            last_error = e
            if attempt < max_attempts
              Services::Logging::SimpleLogger.warn(
                'LLM error - waiting before retry',
                tagged: %i[llm error retry],
                delay_seconds: delay,
                error: e.message
              )
              sleep(delay)
              delay *= 2 # Exponential backoff
              retry
            end
          rescue StandardError => e
            last_error = e
            if attempt < max_attempts
              Services::Logging::SimpleLogger.warn(
                'Unexpected error - waiting before retry',
                tagged: %i[llm error retry],
                delay_seconds: delay,
                error: e.message
              )
              sleep(delay)
              delay *= 2
              retry
            end
          end

          # All retries exhausted
          Services::Logging::SimpleLogger.error(
            'LLM API failed after all attempts',
            tagged: %i[llm error exhausted],
            attempts: attempt
          )
          raise last_error
        end
      end
    end
  end
end
