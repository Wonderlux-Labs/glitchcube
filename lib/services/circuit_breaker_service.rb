# frozen_string_literal: true

require_relative '../circuit_breaker'

module Services
  class CircuitBreakerService
    class << self
      def home_assistant_breaker
        @home_assistant_breaker ||= CircuitBreaker.new(
          name: 'home_assistant',
          failure_threshold: 10,  # More tolerant - art installation needs resilience
          recovery_timeout: 10,   # Shorter recovery - try again quickly
          success_threshold: 1    # One success is enough to close circuit
        )
      end

      def openrouter_breaker
        @openrouter_breaker ||= CircuitBreaker.new(
          name: 'openrouter',
          failure_threshold: 5,
          recovery_timeout: 60,
          success_threshold: 3
        )
      end

      def all_breakers
        [home_assistant_breaker, openrouter_breaker]
      end

      def status
        all_breakers.map(&:status)
      end

      def reset_all
        all_breakers.each(&:close!)
      end
    end
  end
end
