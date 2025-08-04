# frozen_string_literal: true

class CircuitBreaker
  class CircuitOpenError < StandardError; end

  STATES = %i[closed open half_open].freeze

  attr_reader :state, :failure_count, :last_failure_time, :name

  def initialize(name:, failure_threshold: 5, recovery_timeout: 60, success_threshold: 3)
    @name = name
    @failure_threshold = failure_threshold
    @recovery_timeout = recovery_timeout
    @success_threshold = success_threshold
    @failure_count = 0
    @success_count = 0
    @last_failure_time = nil
    @state = :closed
    @mutex = Mutex.new
  end

  def call(&)
    return yield if disabled?

    case state
    when :open
      raise CircuitOpenError, "Circuit breaker #{@name} is OPEN" unless should_attempt_reset?

      attempt_reset
      # After reset, try again in half-open state
      execute_half_open(&)

    when :half_open
      execute_half_open(&)
    else # :closed
      execute_closed(&)
    end
  end

  def open!
    @mutex.synchronize do
      @state = :open
      @last_failure_time = Time.now
      puts "🔴 Circuit breaker #{@name} opened after #{@failure_count} failures"
    end
  end

  def close!
    @mutex.synchronize do
      @state = :closed
      @failure_count = 0
      @success_count = 0
      puts "🟢 Circuit breaker #{@name} closed"
    end
  end

  def half_open!
    @mutex.synchronize do
      @state = :half_open
      @success_count = 0
      puts "🟡 Circuit breaker #{@name} half-open (testing)"
    end
  end

  def disabled?
    # Allow environment variable to disable circuit breakers for testing
    ENV['DISABLE_CIRCUIT_BREAKERS'] == 'true'
  end

  def status
    {
      name: @name,
      state: @state,
      failure_count: @failure_count,
      success_count: @success_count,
      last_failure_time: @last_failure_time,
      next_attempt_at: next_attempt_time
    }
  end

  private

  def execute_closed
    result = yield
    reset_failure_count
    result
  rescue StandardError => e
    record_failure
    open! if @failure_count >= @failure_threshold
    raise e
  end

  def execute_half_open
    result = yield
    record_success
    close! if @success_count >= @success_threshold
    result
  rescue StandardError => e
    record_failure
    open!
    raise e
  end

  def attempt_reset
    @mutex.synchronize do
      @state = :half_open
      @success_count = 0
      puts "🟡 Circuit breaker #{@name} half-open (testing)"
    end
  end

  def should_attempt_reset?
    return false unless @last_failure_time

    Time.now - @last_failure_time > @recovery_timeout
  end

  def next_attempt_time
    return nil unless @state == :open && @last_failure_time

    @last_failure_time + @recovery_timeout
  end

  def record_failure
    @mutex.synchronize do
      @failure_count += 1
      @last_failure_time = Time.now
    end
  end

  def record_success
    @mutex.synchronize do
      @success_count += 1
    end
  end

  def reset_failure_count
    @mutex.synchronize do
      @failure_count = 0 if @failure_count.positive?
    end
  end
end
