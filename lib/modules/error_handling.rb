# frozen_string_literal: true

require_relative '../services/logger_service'

module ErrorHandling
  # Expected operational errors that we handle gracefully
  class OperationalError < StandardError; end
  class ServiceUnavailableError < OperationalError; end
  class RateLimitError < OperationalError; end
  class NetworkTimeoutError < OperationalError; end
  
  # Log and optionally re-raise errors with proper context
  def log_error(error, context = {}, reraise: true)
    # Use LoggerService's api_call method to log errors
    Services::LoggerService.log_api_call(
      service: context[:service] || 'application',
      endpoint: context[:operation] || 'unknown',
      method: context[:method] || 'INTERNAL',
      status: 500,
      error: "#{error.class}: #{error.message}",
      error_class: error.class.name,
      backtrace: error.backtrace&.first(5)&.join("\n"),
      **context
    )
    
    # Also log to console in development for immediate visibility
    if GlitchCube.config.development?
      puts "❌ Error: #{error.class} - #{error.message}"
      puts "   Context: #{context.inspect}" if context.any?
      puts "   Backtrace: #{error.backtrace&.first(3)&.join("\n   ")}"
    end
    
    raise error if reraise
  end
  
  # Handle expected operational errors gracefully
  def handle_operational_error(error, fallback_value = nil, context = {})
    log_error(error, context.merge(operational: true), reraise: false)
    fallback_value
  end
  
  # Wrap a block with comprehensive error handling
  def with_error_handling(operation_name, fallback: nil, reraise_unexpected: true)
    yield
  rescue CircuitBreaker::CircuitOpenError => e
    # Circuit breaker errors are expected operational errors
    handle_operational_error(e, fallback, { operation: operation_name, type: 'circuit_breaker' })
  rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
    # Network timeouts are expected operational errors
    handle_operational_error(e, fallback, { operation: operation_name, type: 'timeout' })
  rescue OperationalError => e
    # Our custom operational errors
    handle_operational_error(e, fallback, { operation: operation_name })
  rescue StandardError => e
    # Unexpected errors should be logged with full context and re-raised
    log_error(e, { operation: operation_name, unexpected: true }, reraise: reraise_unexpected)
    fallback unless reraise_unexpected
  end
  
  # Log deprecation warnings for methods that return false on error
  def deprecated_error_swallow(method_name)
    # Use api_call to log deprecation warnings
    Services::LoggerService.log_api_call(
      service: 'deprecation',
      endpoint: method_name,
      method: 'WARNING',
      status: 200,
      warning: "Method #{method_name} swallows errors and returns false - this pattern is deprecated",
      deprecation: true
    )
  end
end