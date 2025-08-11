# frozen_string_literal: true

require 'logger'
require 'json'
require 'fileutils'

module Services
  # LoggerService is now a compatibility wrapper around SimpleLogger
  # This maintains backward compatibility while delegating to SimpleLogger
  class LoggerService
    class << self
      # Delegate standard logging methods to SimpleLogger
      def debug(msg, **metadata)
        SimpleLogger.debug(msg, **metadata)
      end

      def info(msg, **metadata)
        SimpleLogger.info(msg, **metadata)
      end

      def warn(msg, **metadata)
        SimpleLogger.warn(msg, **metadata)
      end

      def error(msg, **metadata)
        SimpleLogger.error(msg, **metadata)
      end

      def fatal(msg, **metadata)
        SimpleLogger.fatal(msg, **metadata)
      end

      def setup_loggers
        # Legacy method - no longer needed but kept for compatibility
        @setup_loggers ||= ErrorTracker.new
      end

      def general
        # Compatibility method - returns a logger-like object that delegates to SimpleLogger
        self
      end

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
        SimpleLogger.info(
          "Interaction: #{persona}",
          tagged: [:interaction, persona.downcase],
          session_id: session_id,
          user_message: user_message[0..100],
          ai_response: ai_response[0..100],
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

        SimpleLogger.log(
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

        SimpleLogger.log(
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

        SimpleLogger.log(
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

        SimpleLogger.warn(
          message,
          tagged: [:circuit_breaker],
          breaker: name,
          state: state,
          reason: reason
        )
      end

      def track_error(service, error_message)
        ensure_loggers
        @error_tracker.track(service, error_message)
      end

      def error_stats
        ensure_loggers
        @error_tracker.stats
      end

      def error_summary
        ensure_loggers
        @error_tracker.summary
      end

      private

      def ensure_loggers
        # Ensure error tracker is initialized
        @ensure_loggers ||= ErrorTracker.new
      end

      def log_directory
        # For compatibility with ErrorTracker
        root_dir = Cube::Settings.app_root
        if Cube::Settings.test?
          File.join(root_dir, 'logs', 'test')
        else
          File.join(root_dir, 'logs')
        end
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
