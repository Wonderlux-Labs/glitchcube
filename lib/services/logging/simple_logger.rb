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
          line = "[#{timestamp}] [#{level.upcase}] [#{rack_env}] #{msg}"
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
          return unless error.backtrace && backtrace.positive?

          error.backtrace.first(backtrace).each_with_index do |line, i|
            trace_line = "  #{i + 1}: #{line}"
            write_to_file(trace_line)
            puts trace_line if should_echo_to_screen?
          end
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
    end
  end
end
