# frozen_string_literal: true

module Services
  class ErrorHandlerService
    # Expected operational errors that we handle gracefully
    class OperationalError < StandardError; end
    class ServiceUnavailableError < OperationalError; end
    class RateLimitError < OperationalError; end
    class NetworkTimeoutError < OperationalError; end

    ERROR_TRACKING_TTL = 3600 # 1 hour

    def initialize
      @logger = Services::Logging::LoggerService
      @redis = begin
        Redis.new(url: GlitchCube.config.redis_url)
      rescue Redis::CannotConnectError => e
        @logger&.log_api_call(
          service: 'ErrorHandlerService',
          endpoint: 'initialize',
          error: "Redis unavailable: #{e.message}"
        )
        nil
      end
      @rate_limit_cache = {}
    end

    # Main error handling method - combines logging, tracking, and self-healing
    def handle_error(error, context = {})
      # Always log the error first
      log_error(error, context)

      # Track error occurrence for self-healing
      if self_healing_enabled?
        occurrence_count = track_error_occurrence(error, context)

        # Check if we should attempt self-healing
        if occurrence_count >= error_recurrence_threshold
          attempt_self_healing(error, context)
        end
      end

      # Return fallback value if provided
      context[:fallback]
    rescue StandardError => e
      # If error handling itself fails, just log and continue
      @logger&.log_api_call(
        service: 'ErrorHandlerService',
        endpoint: 'handle_error',
        error: "Error handler failed: #{e.message}"
      )
      context[:fallback]
    end

    # Log error with proper context
    def log_error(error, context = {})
      @logger&.log_api_call(
        service: context[:service] || 'application',
        endpoint: context[:operation] || 'unknown',
        method: context[:method] || 'INTERNAL',
        status: 500,
        error: "#{error.class}: #{error.message}",
        error_class: error.class.name,
        backtrace: error.backtrace&.first(5)&.join("\n"),
        **context.except(:fallback)
      )

      # Console logging in development
      return unless GlitchCube.config.development?

      puts "❌ Error: #{error.class} - #{error.message}"
      puts "   Context: #{context.inspect}" if context.any?
      puts "   Backtrace: #{error.backtrace&.first(3)&.join("\n   ")}"
    end

    # Wrap a block with comprehensive error handling
    def with_error_handling(operation_name, fallback: nil, reraise_unexpected: true)
      yield
    rescue CircuitBreaker::CircuitOpenError => e
      handle_error(e, { operation: operation_name, type: 'circuit_breaker', fallback: fallback, operational: true })
    rescue Net::OpenTimeout, Net::ReadTimeout => e
      handle_error(e, { operation: operation_name, type: 'timeout', fallback: fallback, operational: true })
    rescue OperationalError => e
      handle_error(e, { operation: operation_name, fallback: fallback, operational: true })
    rescue StandardError => e
      handle_error(e, { operation: operation_name, fallback: fallback, unexpected: true })
      raise if reraise_unexpected

      fallback
    end

    # Instance method for error healing
    def with_error_healing(&block)
      block.call
    rescue StandardError => e
      caller_info = caller_locations(1, 1).first
      context = {
        file: caller_info.path,
        line: caller_info.lineno,
        method: caller_info.label,
        service: self.class.name,
        timestamp: Time.now.iso8601,
        environment: GlitchCube.config.rack_env
      }

      handle_error(e, context)
      raise # Re-raise after handling
    end

    private

    def self_healing_enabled?
      GlitchCube.config.self_healing_enabled?
    end

    def error_recurrence_threshold
      GlitchCube.config.self_healing_error_threshold || 3
    end

    def criticality_threshold
      GlitchCube.config.self_healing_min_confidence || 0.7
    end

    def track_error_occurrence(error, context)
      return 0 unless @redis

      error_key = generate_error_key(error, context)
      occurrence_key = "glitchcube:error_occurrences:#{error_key}"

      occurrence_count = @redis.incr(occurrence_key)
      @redis.expire(occurrence_key, ERROR_TRACKING_TTL)

      occurrence_count
    end

    def generate_error_key(error, context)
      key_parts = [
        error.class.name,
        context[:file]&.split('/')&.last,
        context[:line],
        context[:method]
      ].compact

      Digest::SHA256.hexdigest(key_parts.join(':'))
    end

    def attempt_self_healing(error, context)
      # Check if we've already proposed a fix for this error
      error_key = generate_error_key(error, context)
      if @redis&.exists?("glitchcube:fixed_errors:#{error_key}")
        return {
          action: 'already_analyzed',
          message: 'Fix already proposed for this error'
        }
      end

      # Delegate to ErrorHandlingLLM for self-healing if it exists
      return unless defined?(Services::System::ErrorHandlingLLM)

      llm_handler = Services::System::ErrorHandlingLLM.new
      llm_handler.handle_error(error, context)
    end

    # Class methods for module compatibility
    class << self
      def instance
        @instance ||= new
      end

      def handle_error(error, context = {})
        instance.handle_error(error, context)
      end

      def with_error_handling(operation_name, fallback: nil, reraise_unexpected: true, &)
        instance.with_error_handling(operation_name, fallback: fallback, reraise_unexpected: reraise_unexpected, &)
      end

      def log_error(error, context = {})
        instance.log_error(error, context)
      end
    end
  end
end

# Compatibility module for easy inclusion
module ErrorHandling
  def handle_error(error, context = {})
    Services::ErrorHandlerService.handle_error(error, context)
  end

  def log_error(error, context = {}, reraise: true)
    Services::ErrorHandlerService.log_error(error, context)
    raise error if reraise
  end

  def handle_operational_error(error, fallback_value = nil, context = {})
    Services::ErrorHandlerService.handle_error(
      error,
      context.merge(operational: true, fallback: fallback_value)
    )
  end

  def with_error_handling(operation_name, fallback: nil, reraise_unexpected: true, &)
    Services::ErrorHandlerService.with_error_handling(
      operation_name,
      fallback: fallback,
      reraise_unexpected: reraise_unexpected,
      &
    )
  end

  def with_error_healing(&)
    Services::ErrorHandlerService.instance.with_error_healing(&)
  end
end
