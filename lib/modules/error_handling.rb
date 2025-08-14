# frozen_string_literal: true

module Modules
  module ErrorHandling
    # Expected operational errors that we handle gracefully
    class OperationalError < StandardError; end
    class ServiceUnavailableError < OperationalError; end
    class RateLimitError < OperationalError; end
    class NetworkTimeoutError < OperationalError; end

    # Delegate to the new error handler service for better functionality
    def handle_error(error, context = {})
      Services::ErrorHandlerService.handle_error(error, context)
    end

    # Log and optionally re-raise errors with proper context
    def log_error(error, context = {}, reraise: true)
      Services::ErrorHandlerService.log_error(error, context)
      raise error if reraise
    end

    # Handle expected operational errors gracefully
    def handle_operational_error(error, fallback_value = nil, context = {})
      Services::ErrorHandlerService.handle_error(
        error,
        context.merge(operational: true, fallback: fallback_value)
      )
    end

    # Wrap a block with comprehensive error handling
    def with_error_handling(operation_name, fallback: nil, reraise_unexpected: true, &)
      Services::ErrorHandlerService.with_error_handling(
        operation_name,
        fallback: fallback,
        reraise_unexpected: reraise_unexpected,
        &
      )
    end

    # New method for error healing functionality
    def with_error_healing(&)
      Services::ErrorHandlerService.instance.with_error_healing(&)
    end
  end
end
