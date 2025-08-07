# frozen_string_literal: true

require 'logger'
require 'json'
require 'fileutils'
require_relative '../cube/settings'

module Services
  # UnifiedLoggerService - A comprehensive logging system that provides:
  # - Single unified log file with excellent readability
  # - Structured JSON metadata for parsing/analysis
  # - Contextual logging with request/session correlation
  # - Clean, colorized console output
  # - Automatic log rotation and management
  class UnifiedLoggerService
    class << self
      attr_reader :logger, :context_store

      def setup!
        return self if @logger # Prevent recursive setup

        @setting_up = true # Set flag before any operations
        @context_store = Thread.current[:logger_context] = {}
        @logger = create_unified_logger
        @start_time = Time.now
        @setting_up = false # Clear setup flag

        # Log service startup if logger creation succeeded
        # Use a direct logger call to avoid recursion
        if @logger
          log_direct(:info, '🎲 Glitch Cube Unified Logger initialized')
          log_direct(:info, "📂 Logging to: #{log_file_path}")
        end

        self
      end

      def reset!
        @logger = nil
        @context_store = nil
        @setting_up = false
        Thread.current[:logger_context] = nil
      end

      # Standard log levels with enhanced formatting
      def debug(message, **metadata)
        log(:debug, message, **metadata)
      end

      def info(message, **metadata)
        log(:info, message, **metadata)
      end

      def warn(message, **metadata)
        log(:warn, message, **metadata)
      end

      def error(message, **metadata)
        log(:error, message, **metadata)
      end

      def fatal(message, **metadata)
        log(:fatal, message, **metadata)
      end

      # Context management for request/session correlation
      def with_context(**context_data)
        old_context = current_context.dup
        current_context.merge!(context_data)

        # Only log context updates if logger is already set up to avoid recursion
        debug('Context updated', context: context_data) if @logger
        yield
      ensure
        Thread.current[:logger_context] = old_context
      end

      def current_context
        Thread.current[:logger_context] ||= {}
      end

      # Structured logging methods for specific event types
      def api_call(service:, endpoint:, method: 'POST', status: nil, duration: nil, error: nil, **metadata)
        status_emoji = status_emoji_for(status)
        message = "#{status_emoji} API #{service.upcase} #{method} #{endpoint}"
        message += " #{status}" if status
        message += " (#{duration}ms)" if duration
        message += " - #{error}" if error

        level = if error
                  :error
                else
                  (status && status >= 400 ? :warn : :info)
                end

        log(level, message,
            type: 'api_call',
            service: service,
            method: method,
            endpoint: endpoint,
            status: status,
            duration_ms: duration,
            error: error,
            **metadata)
      end

      def conversation(user_message:, ai_response:, mood: nil, confidence: nil, model: nil, **metadata)
        confidence_pct = confidence ? (confidence * 100).round : nil
        message = '💬 Conversation'
        message += " | #{mood}" if mood
        message += " | #{confidence_pct}%" if confidence_pct
        message += " | #{model}" if model

        log(:info, message,
            type: 'conversation',
            user_message: truncate_message(user_message),
            ai_response: truncate_message(ai_response),
            mood: mood,
            confidence: confidence,
            model: model,
            **metadata)
      end

      def system_event(event:, **metadata)
        emoji = event_emoji_for(event)
        message = "#{emoji} System: #{event.to_s.tr('_', ' ').capitalize}"

        log(:info, message,
            type: 'system_event',
            event: event,
            **metadata)
      end

      def home_assistant(action:, entity: nil, service: nil, success: nil, error: nil, **metadata)
        emoji = if success.nil?
                  '🏠'
                else
                  (success ? '✅' : '❌')
                end
        message = "#{emoji} HA #{action}"
        message += " #{entity}" if entity
        message += " #{service}" if service
        message += " - #{error}" if error

        level = error ? :error : :info

        log(level, message,
            type: 'home_assistant',
            action: action,
            entity: entity,
            service: service,
            success: success,
            error: error,
            **metadata)
      end

      def performance(operation:, duration:, **metadata)
        color = case duration
                when 0..500 then '🟢'
                when 501..2000 then '🟡'
                else '🔴'
                end

        message = "#{color} Performance: #{operation} (#{duration}ms)"

        log(:info, message,
            type: 'performance',
            operation: operation,
            duration_ms: duration,
            **metadata)
      end

      def circuit_breaker(name:, state:, reason: nil, **metadata)
        emoji = case state
                when :open then '🔴'
                when :closed then '🟢'
                when :half_open then '🟡'
                else '⚪'
                end

        message = "#{emoji} Circuit breaker #{name} -> #{state.upcase}"
        message += " (#{reason})" if reason

        level = state == :open ? :warn : :info

        log(level, message,
            type: 'circuit_breaker',
            name: name,
            state: state,
            reason: reason,
            **metadata)
      end

      private

      def create_unified_logger
        ensure_log_directory

        logger = Logger.new(log_file_path, 'daily', 10)
        logger.level = Cube::Settings.log_level
        logger.formatter = method(:format_log_entry)

        logger
      rescue StandardError => e
        # Fallback to STDOUT if file logging fails
        # Use puts instead of warn to avoid recursion
        puts "Failed to setup file logger: #{e.message}. Using STDOUT."
        logger = Logger.new($stdout)
        logger.level = Cube::Settings.log_level
        logger.formatter = method(:format_log_entry)
        logger
      end

      def log(level, message, **metadata)
        # If logger isn't set up, initialize it
        unless @logger
          # Prevent infinite recursion during setup
          return if @setting_up

          @setting_up = true
          setup!
          return if @logger.nil? # Give up if setup failed
        end

        log_direct(level, message, **metadata)
      end

      def log_direct(level, message, **metadata)
        return unless @logger

        # Build complete log data with context
        log_data = {
          timestamp: Time.now.iso8601,
          level: level.to_s.upcase,
          message: message,
          context: current_context.merge(metadata.compact)
        }

        # Write to file logger
        @logger.send(level, log_data.to_json)

        # Also write human-readable to console if in development
        return unless Cube::Settings.development? || Cube::Settings.log_level == Logger::DEBUG

        console_output = format_console_message(level, message, **metadata)
        puts console_output
      end

      def format_log_entry(severity, time, _progname, msg)
        # Parse JSON log data for pretty formatting

        data = JSON.parse(msg)

        # Core log line with timestamp and level
        formatted = "[#{time.strftime('%H:%M:%S')}] #{severity.ljust(5)} #{data['message']}"

        # Add context information if present
        context = data['context'] || {}
        if context.any?
          context_parts = []

          # Show important context fields inline
          context_parts << "req:#{context['request_id']}" if context['request_id']
          context_parts << "sess:#{context['session_id']}" if context['session_id']
          context_parts << "conv:#{context['conversation_id']}" if context['conversation_id']

          formatted += " [#{context_parts.join(' ')}]" if context_parts.any?

          # Show additional metadata on separate lines for complex data
          complex_data = context.except('request_id', 'session_id', 'conversation_id', 'type')
          if complex_data.any?
            complex_data.each do |key, value|
              next if value.nil? || (value.respond_to?(:empty?) && value.empty?)

              formatted += "\n    #{key}: #{format_value(value)}"
            end
          end
        end

        "#{formatted}\n"
      rescue JSON::ParserError
        # Fallback for non-JSON messages
        "[#{time.strftime('%H:%M:%S')}] #{severity.ljust(5)} #{msg}\n"
      end

      def format_console_message(level, message, **metadata)
        level_colors = {
          debug: "\e[37m",   # White
          info: "\e[36m",    # Cyan
          warn: "\e[33m",    # Yellow
          error: "\e[31m",   # Red
          fatal: "\e[35m"    # Magenta
        }

        color = level_colors[level] || "\e[0m"
        reset = "\e[0m"

        formatted = "#{color}#{message}#{reset}"

        # Add important metadata inline for console
        formatted += " (#{metadata[:duration_ms]}ms)" if metadata[:duration_ms]

        formatted += " [#{metadata[:status]}]" if metadata[:status]

        formatted
      end

      def format_value(value)
        case value
        when String
          value.length > 100 ? "#{value[0..97]}..." : value
        when Hash, Array
          value.to_json
        else
          value.to_s
        end
      end

      def status_emoji_for(status)
        case status
        when 200..299 then '✅'
        when 300..399 then '🔄'
        when 400..499 then '⚠️'
        when 500..599 then '❌'
        else '📡'
        end
      end

      def event_emoji_for(event)
        case event.to_s
        when /battery/ then '🔋'
        when /temperature/ then '🌡️'
        when /movement/ then '🚀'
        when /startup|boot/ then '⚡'
        when /shutdown/ then '🛑'
        when /error|fail/ then '❌'
        when /success/ then '✅'
        else '🎯'
        end
      end

      def truncate_message(message, limit = 200)
        return message if message.nil? || message.length <= limit

        "#{message[0..(limit - 4)]}..."
      end

      def ensure_log_directory
        dir = log_directory
        FileUtils.mkdir_p(dir) unless File.directory?(dir)

        unless File.writable?(dir)
          # Use puts instead of warn to avoid recursion
          puts "Log directory #{dir} is not writable. Attempting to fix permissions..."
          FileUtils.chmod(0o755, dir)
        end
      rescue StandardError => e
        # Use puts instead of warn to avoid recursion
        puts "Failed to create log directory: #{e.message}"
        raise e
      end

      def log_directory
        root_dir = Cube::Settings.app_root
        if Cube::Settings.test?
          File.join(root_dir, 'logs', 'test')
        else
          File.join(root_dir, 'logs')
        end
      end

      def log_file_path
        File.join(log_directory, 'glitchcube.log')
      end
    end
  end
end
