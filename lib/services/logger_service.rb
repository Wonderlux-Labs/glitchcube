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
        @interaction_logger = create_file_logger('interactions.log')
        @api_logger = create_file_logger('api_calls.log')
        @tts_logger = create_file_logger('tts.log')
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
        @interaction_logger.puts format_interaction(interaction_data)
        
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

        @api_logger.puts "#{Time.now.strftime('%H:%M:%S')} #{status_emoji} #{service.upcase} #{method} #{endpoint} #{status} (#{duration}ms)#{error ? " - #{error}" : ''}"
        
        # Also log to general
        general.info("API_CALL: #{api_data.to_json}")

        # Track errors
        track_error(service, error) if error
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
        @tts_logger.puts "#{Time.now.strftime('%H:%M:%S')} #{status_emoji} \"#{tts_data[:message]}\"#{error ? " - #{error}" : ''}"
        
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

        message = "Circuit breaker #{name} -> #{state.upcase}#{reason ? " (#{reason})" : ''}"
        puts "#{emoji} #{message}"  # Still show in console for immediate feedback
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
        FileUtils.mkdir_p(log_directory)
      end

      def log_directory
        File.join(Dir.pwd, 'logs')
      end

      def create_logger(filename, level = Logger::INFO)
        logger = Logger.new(File.join(log_directory, filename), 'daily')
        logger.level = level
        logger.formatter = proc do |severity, datetime, progname, msg|
          "[#{datetime.strftime('%Y-%m-%d %H:%M:%S')}] #{severity}: #{msg}\n"
        end
        logger
      end

      def create_file_logger(filename)
        File.open(File.join(log_directory, filename), 'a').tap do |file|
          file.sync = true  # Auto-flush for real-time viewing
        end
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
        end.sort_by { |e| -e[:count] }  # Sort by frequency
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
        File.write(@error_file, JSON.pretty_generate(@errors))
      end
    end
  end
end