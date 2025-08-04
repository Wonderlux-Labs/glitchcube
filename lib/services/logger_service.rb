# frozen_string_literal: true

require 'logger'
require 'json'
require 'fileutils'

module Services
  class LoggerService
    class << self
      def setup_loggers
        ensure_log_directory

        @general_logger = create_logger('general.log', Logger::INFO)
        @interaction_logger = create_logger('interactions.log', Logger::INFO)
        @api_logger = create_logger('api_calls.log', Logger::INFO)
        @tts_logger = create_logger('tts.log', Logger::INFO)
        @requests_logger = create_logger('requests.log', Logger::INFO)
        @error_tracker = ErrorTracker.new
      rescue StandardError => e
        # Fallback to STDOUT if file logging fails
        puts "Failed to setup file loggers: #{e.message}. Using STDOUT."
        @general_logger = Logger.new($stdout)
        @interaction_logger = @api_logger = @tts_logger = @requests_logger = @general_logger
        @error_tracker = ErrorTracker.new
      end

      def general
        @general_logger ||= setup_loggers
        @general_logger
      end

      def log_interaction(user_message:, ai_response:, mood:, confidence:, session_id: nil, context: {})
        ensure_loggers

        interaction_data = {
          timestamp: Time.now.iso8601,
          session_id: session_id,
          user_message: user_message,
          ai_response: ai_response,
          mood: mood,
          confidence: confidence,
          context: context
        }

        # Human-readable interaction log
        @interaction_logger.info(format_interaction(interaction_data))

        # Also log to general with JSON for structured parsing
        general.info("INTERACTION: #{interaction_data.to_json}")
      end

      def log_api_call(service:, endpoint:, method: 'POST', status: nil, duration: nil, error: nil, **context)
        ensure_loggers

        api_data = {
          timestamp: Time.now.iso8601,
          service: service,
          endpoint: endpoint,
          method: method,
          status: status,
          duration_ms: duration,
          error: error
        }.merge(context)

        # Human-readable API log
        status_emoji = case status
                       when 200..299 then '✅'
                       when 400..499 then '⚠️ '
                       when 500..599 then '❌'
                       else '🔄'
                       end

        @api_logger.info("#{status_emoji} #{service.upcase} #{method} #{endpoint} #{status} (#{duration}ms)#{" - #{error}" if error}")

        # Also log to general
        general.info("API_CALL: #{api_data.to_json}")

        # Track errors
        track_error(service, error) if error
      end

      def log_request(method:, path:, status:, duration:, params: {}, user_agent: nil, ip: nil, error: nil)
        ensure_loggers

        request_data = {
          timestamp: Time.now.iso8601,
          method: method,
          path: path,
          status: status,
          duration_ms: duration,
          params: params,
          user_agent: user_agent,
          ip: ip,
          error: error
        }

        # Human-readable request log
        status_emoji = case status
                       when 200..299 then '✅'
                       when 300..399 then '🔄'
                       when 400..499 then '⚠️ '
                       when 500..599 then '❌'
                       else '❓'
                       end

        params_str = params.empty? ? '' : " #{params.to_json}"
        error_str = error ? " - ERROR: #{error}" : ''

        @requests_logger.info("#{status_emoji} #{method} #{path} #{status} (#{duration}ms)#{params_str}#{error_str}")

        # Also log to general with JSON
        general.info("REQUEST: #{request_data.to_json}")

        # Track errors
        track_error('web_request', error) if error
      end

      def log_tts(message:, success:, duration: nil, error: nil)
        ensure_loggers

        tts_data = {
          timestamp: Time.now.iso8601,
          message: message[0..100] + (message.length > 100 ? '...' : ''),
          success: success,
          duration_ms: duration,
          error: error
        }

        # Human-readable TTS log
        status_emoji = success ? '🔊' : '🔇'
        @tts_logger.info("#{status_emoji} \"#{tts_data[:message]}\"#{" - #{error}" if error}")

        # Also log to general
        general.info("TTS: #{tts_data.to_json}")

        # Track TTS errors
        track_error('tts', error) if error
      end

      def log_circuit_breaker(name:, state:, reason: nil)
        ensure_loggers

        emoji = case state
                when :open then '🔴'
                when :closed then '🟢'
                when :half_open then '🟡'
                else '⚪'
                end

        message = "Circuit breaker #{name} -> #{state.upcase}#{" (#{reason})" if reason}"
        puts "#{emoji} #{message}" # Still show in console for immediate feedback
        general.warn("CIRCUIT_BREAKER: #{message}")
      end

      def track_error(service, error_message)
        @error_tracker.track(service, error_message)
      end

      def error_stats
        @error_tracker.stats
      end

      def error_summary
        @error_tracker.summary
      end

      private

      def ensure_loggers
        setup_loggers unless @general_logger
      end

      def ensure_log_directory
        dir = log_directory
        FileUtils.mkdir_p(dir) unless File.directory?(dir)

        # Ensure directory is writable
        unless File.writable?(dir)
          puts "Warning: Log directory #{dir} is not writable. Trying to fix permissions..."
          begin
            FileUtils.chmod(0o755, dir)
          rescue StandardError => e
            puts "Failed to fix permissions: #{e.message}"
          end
        end
      rescue StandardError => e
        puts "Failed to create log directory: #{e.message}"
        raise e
      end

      def log_directory
        # Use APP_ROOT if set (for containers), otherwise use current directory
        root_dir = ENV['APP_ROOT'] || Dir.pwd
        File.join(root_dir, 'logs')
      end

      def create_logger(filename, level = Logger::INFO)
        logger = Logger.new(File.join(log_directory, filename), 'daily')
        logger.level = level

        # Use simple formatter for specialized logs (interactions, api, etc.)
        # Use detailed formatter for general log
        logger.formatter = if filename == 'general.log'
                             proc do |severity, datetime, _progname, msg|
                               "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
                             end
                           else
                             # Simpler format for specialized logs - message only
                             proc do |_severity, _datetime, _progname, msg|
                               "#{msg}\n"
                             end
                           end

        logger
      end

      def format_interaction(data)
        <<~INTERACTION

          ═══════════════════════════════════════════════════════════════
          #{data[:timestamp]} | Session: #{data[:session_id] || 'N/A'} | Mood: #{data[:mood]} | Confidence: #{(data[:confidence] * 100).round}%
          ═══════════════════════════════════════════════════════════════

          👤 USER: #{data[:user_message]}

          🎲 GLITCH CUBE: #{data[:ai_response]}

          Context: #{data[:context].empty? ? 'None' : data[:context].inspect}
          ───────────────────────────────────────────────────────────────
        INTERACTION
      end
    end

    class ErrorTracker
      def initialize
        @error_file = File.join(Services::LoggerService.send(:log_directory), 'errors.json')
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
        @errors.values.map do |error_data|
          {
            service: error_data[:service],
            error: error_data[:error],
            count: error_data[:count],
            first_seen: error_data[:first_occurrence],
            last_seen: error_data[:last_occurrence]
          }
        end.sort_by { |e| -e[:count] } # Sort by frequency
      end

      def summary
        total_errors = @errors.values.sum { |e| e[:count] }
        services = @errors.values.group_by { |e| e[:service] }

        {
          total_errors: total_errors,
          unique_errors: @errors.size,
          by_service: services.transform_values { |errors| errors.sum { |e| e[:count] } },
          top_errors: stats.first(5)
        }
      end

      private

      def load_errors
        return {} unless File.exist?(@error_file)

        parsed = JSON.parse(File.read(@error_file))
        # Ensure all loaded errors have proper structure
        parsed.transform_values do |error_data|
          error_data.transform_keys(&:to_sym)
        end
      rescue JSON::ParserError
        {}
      end

      def save_errors
        # Ensure directory exists before writing
        dir = File.dirname(@error_file)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)

        File.write(@error_file, JSON.pretty_generate(@errors))
      rescue StandardError => e
        # If we can't write to file, just log to console
        puts "Warning: Could not save error tracking file: #{e.message}"
      end
    end
  end
end
