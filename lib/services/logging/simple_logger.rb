# frozen_string_literal: true

require 'fileutils'

module Services
  module Logging
    class SimpleLogger
      LOG_LEVELS = { debug: 0, info: 1, warn: 2, error: 3, fatal: 4 }.freeze

      class << self
        def log(msg:, level: :info, tagged: [], **metadata)
          return if below_log_level?(level)

          timestamp = Time.now.strftime('%H:%M:%S.%3N')
          caller_info = extract_caller
          tags = normalize_tags(tagged)

          # Format: [timestamp] [LEVEL] [ENV] message #tag1 #tag2 (caller) key=value
          colored_level = colorize_level(level)
          line = "[#{timestamp}] [#{colored_level}] [#{rack_env}] #{msg}"
          line += " #{tags.map { |t| "##{t}" }.join(' ')}" unless tags.empty?
          line += " (#{caller_info})"
          line += " #{format_metadata(metadata)}" unless metadata.empty?

          write_to_file(line)
          puts line if should_echo_to_screen?
        end

        def log_error(error:, message: nil, backtrace: 5, **metadata)
          msg = message || error.message

          log(
            msg: "ERROR: #{msg}",
            level: :error,
            tagged: [:error],
            error_class: error.class.name,
            **metadata
          )

          # Stack trace to file and screen
          return unless error.backtrace&.length&.positive?

          error.backtrace.first(backtrace).each_with_index do |line, i|
            trace_line = "  #{i + 1}: #{line}"
            write_to_file(trace_line)
            puts trace_line if should_echo_to_screen?
          end
        rescue StandardError => e
          # Logger should never crash and mask the original error
          # Output to stderr as last resort to ensure error visibility
          warn "LOGGER ERROR: Failed to log error - #{e.message}"
          warn "ORIGINAL ERROR: #{error.class.name} - #{error.message}"
          warn "ORIGINAL BACKTRACE: #{error.backtrace&.first(3)&.join(', ')}" if error.respond_to?(:backtrace)
        end

        # Convenience methods
        def debug(msg, **); log(msg: msg, level: :debug, **); end
        def info(msg, **); log(msg: msg, level: :info, **); end
        def warn(msg, **); log(msg: msg, level: :warn, **); end
        def error(msg, **); log(msg: msg, level: :error, **); end
        def fatal(msg, **); log(msg: msg, level: :fatal, **); end

        # Screen-only debugging
        def puts(msg, **metadata)
          timestamp = Time.now.strftime('%H:%M:%S.%3N')
          line = "[#{timestamp}] #{msg}"
          line += " #{format_metadata(metadata)}" unless metadata.empty?
          ::Kernel.puts line
        end

        # Compatibility method for with_context (from old logger)
        def with_context(**context_data)
          # Store context temporarily for this block
          old_context = @current_context
          @current_context = (old_context || {}).merge(context_data)

          yield self
        ensure
          @current_context = old_context
        end

        # Compatibility methods for old UnifiedLoggerService
        def performance(operation:, duration:, **metadata)
          info("Performance: #{operation}", tagged: [:performance], operation: operation, duration_ms: duration, **metadata)
        end

        # Specialized logging methods (previously in LoggerService)
        def log_interaction(user_message:, ai_response:, persona:, confidence: nil, session_id: nil, context: {})
          interaction_data = {
            timestamp: Time.now.iso8601,
            session_id: session_id,
            user_message: user_message,
            ai_response: ai_response,
            persona: persona,
            context: context
          }

          # Only add confidence if provided (for backward compatibility)
          interaction_data[:confidence] = confidence if confidence

          # Use SimpleLogger with appropriate tags
          info(
            "Interaction: #{persona}",
            tagged: [:interaction, persona.downcase],
            session_id: session_id,
            user_message: user_message,
            ai_response: ai_response,
            confidence: confidence
          )
        end

        def log_api_call(service:, endpoint:, method: 'POST', status: nil, duration: nil, error: nil, url: nil, **context)
          status_emoji = case status
                         when 200..299 then '✅'
                         when 400..499 then '⚠️'
                         when 500..599 then '❌'
                         else '🔄'
                         end

          message = "#{status_emoji} #{service.upcase} #{method} #{endpoint} #{status} (#{duration}ms)"
          message += " - #{error}" if error

          level = error ? :error : :info
          tags = [:api, service.downcase]

          log(
            msg: message,
            level: level,
            tagged: tags,
            service: service,
            endpoint: endpoint,
            method: method,
            status: status,
            duration_ms: duration,
            url: url,
            **context
          )

          # Track errors
          track_error(service, error) if error
        end

        def log_request(method:, path:, status:, duration:, params: {}, user_agent: nil, ip: nil, error: nil)
          status_emoji = case status
                         when 200..299 then '✅'
                         when 300..399 then '🔄'
                         when 400..499 then '⚠️'
                         when 500..599 then '❌'
                         else '❓'
                         end

          message = "#{status_emoji} #{method} #{path} #{status} (#{duration}ms)"
          message += " - ERROR: #{error}" if error

          level = error ? :error : :info

          log(
            msg: message,
            level: level,
            tagged: [:request],
            method: method,
            path: path,
            status: status,
            duration_ms: duration,
            params: params,
            user_agent: user_agent,
            ip: ip
          )

          # Track errors
          track_error('web_request', error) if error
        end

        def log_tts(message:, success:, duration: nil, error: nil, **_extra_params)
          status_emoji = success ? '🔊' : '🔇'
          truncated_msg = message[0..100] + (message.length > 100 ? '...' : '')

          log_msg = "#{status_emoji} \"#{truncated_msg}\""
          log_msg += " - #{error}" if error

          log(
            msg: log_msg,
            level: error ? :error : :info,
            tagged: [:tts],
            success: success,
            duration_ms: duration
          )

          # Track TTS errors
          track_error('tts', error) if error
        end

        def log_circuit_breaker(name:, state:, reason: nil)
          emoji = case state
                  when :open then '🔴'
                  when :closed then '🟢'
                  when :half_open then '🟡'
                  else '⚪'
                  end

          message = "#{emoji} Circuit breaker #{name} -> #{state.upcase}"
          message += " (#{reason})" if reason

          warn(
            message,
            tagged: [:circuit_breaker],
            breaker: name,
            state: state,
            reason: reason
          )
        end

        def track_error(service, error_message)
          @error_tracker ||= ErrorTracker.new
          if @error_tracker.nil?
            warn "⚠️  ErrorTracker failed to initialize - cannot track error: #{service}:#{error_message}"
          else
            @error_tracker.track(service, error_message)
          end
        end

        def error_stats
          ensure_error_tracker
          @error_tracker.stats
        end

        def error_summary
          ensure_error_tracker
          @error_tracker.summary
        end

        def general
          # Compatibility method - returns self for logger-like behavior
          self
        end

        def setup_loggers
          # Legacy method - no longer needed but kept for compatibility
          # SimpleLogger auto-creates directories as needed
          ensure_log_directory
          # Write a test log to ensure file is created (for test compatibility)
          write_to_file('[SETUP] Logger initialized')
        end

        # Public accessor for log directory path
        def log_directory_path
          log_directory
        end

        # Public accessor for log file path
        def log_file_path
          File.join(log_directory, 'current.log')
        end

        private

        def below_log_level?(level)
          level_value = LOG_LEVELS[level] || LOG_LEVELS[:info]
          current_value = LOG_LEVELS[current_log_level] || LOG_LEVELS[:info]
          level_value < current_value
        end

        def current_log_level
          level_str = ENV['LOG_LEVEL'] || 'info'
          level_str.to_sym
        end

        def should_echo_to_screen?
          ENV['LOG_TO_SCREEN'] == 'true'
        end

        def rack_env
          (ENV['RACK_ENV'] || 'development').upcase
        end

        def extract_caller
          # Skip SimpleLogger internal calls to find actual caller
          caller_location = caller_locations(3, 1).first
          return 'unknown' unless caller_location

          file = caller_location.path.split('/').last
          line = caller_location.lineno
          "#{file}:#{line}"
        end

        def normalize_tags(tagged)
          return [] unless tagged

          Array(tagged).map(&:to_s).reject(&:empty?)
        end

        def colorize_level(level)
          return level.upcase unless should_echo_to_screen?

          case level
          when :debug
            "\e[90m#{level.upcase}\e[0m"  # Dark gray
          when :info
            "\e[36m#{level.upcase}\e[0m"   # Cyan
          when :warn
            "\e[33m#{level.upcase}\e[0m"   # Yellow
          when :error
            "\e[31m#{level.upcase}\e[0m"   # Red
          when :fatal
            "\e[35m#{level.upcase}\e[0m"   # Magenta
          else
            level.upcase
          end
        end

        def format_metadata(metadata)
          # Merge current context with provided metadata
          all_metadata = (@current_context || {}).merge(metadata)
          all_metadata.map { |k, v| "#{k}=#{v}" }.join(' ')
        end

        def write_to_file(line)
          ensure_log_directory
          File.open(log_file_path, 'a') { |f| f.puts line }
        rescue StandardError => e
          # In CI, silently fail logging to file (tests don't need persistent logs)
          # In dev/prod, show the error
          unless ENV['CI'] == 'true' || ENV['GITHUB_ACTIONS'] == 'true'
            ::Kernel.puts "LOG ERROR: #{e.message}"
            ::Kernel.puts line
          end
        end

        def ensure_log_directory
          return if @log_dir_ensured

          dir = log_directory
          FileUtils.mkdir_p(dir) unless File.directory?(dir)
          @log_dir_ensured = true
        rescue StandardError => e
          ::Kernel.puts "Failed to create log directory: #{e.message}"
        end

        def ensure_error_tracker
          # Ensure error tracker is initialized
          @ensure_error_tracker ||= ErrorTracker.new
        end

        def log_directory
          # In CI or when APP_ROOT is set to /custom/path, use a fallback
          root_dir = if defined?(Cube::Settings) && Cube::Settings.app_root != '/custom/path'
                       Cube::Settings.app_root
                     elsif ENV['GITHUB_ACTIONS'] == 'true' || ENV['CI'] == 'true'
                       ENV['GITHUB_WORKSPACE'] || Dir.pwd
                     else
                       Dir.pwd
                     end

          if ENV['RACK_ENV'] == 'test' || ENV['ENVIRONMENT'] == 'test'
            File.join(root_dir, 'logs', 'test')
          else
            File.join(root_dir, 'logs')
          end
        end
      end

      class ErrorTracker
        def initialize
          @error_file = File.join(SimpleLogger.send(:log_directory), 'errors.json')
          @errors = load_errors
        end

        def track(service, error_message)
          error_key = "#{service}:#{error_message}"

          if @errors[error_key]
            @errors[error_key][:count] += 1
            @errors[error_key][:last_occurrence] = Time.now.iso8601
          else
            @errors[error_key] = {
              service: service,
              error: error_message,
              count: 1,
              first_occurrence: Time.now.iso8601,
              last_occurrence: Time.now.iso8601
            }
          end

          save_errors
        end

        def stats
          errors = @errors.values.map do |error_data|
            {
              service: error_data[:service],
              error: error_data[:error],
              count: error_data[:count],
              first_seen: error_data[:first_occurrence],
              last_seen: error_data[:last_occurrence]
            }
          end
          errors.sort_by { |e| -e[:count] } # Sort by frequency
        end

        def summary
          total_errors = @errors.values.sum { |e| e[:count] }
          services = @errors.values.group_by { |e| e[:service] }

          {
            total_errors: total_errors,
            unique_errors: @errors.size,
            by_service: services.transform_values { |service_errors| service_errors.sum { |e| e[:count] } }
          }
        end

        private

        def load_errors
          return {} unless File.exist?(@error_file)

          JSON.parse(File.read(@error_file), symbolize_names: true)
        rescue JSON::ParserError, StandardError
          {}
        end

        def save_errors
          File.write(@error_file, JSON.pretty_generate(@errors))
        rescue StandardError => e
          # Silently fail saving errors (to avoid infinite error loops)
          puts "Failed to save error tracking: #{e.message}" unless ENV['CI'] == 'true'
        end
      end
    end
  end
end
