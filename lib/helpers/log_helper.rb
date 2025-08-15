# frozen_string_literal: true

module Helpers
  # LogHelper delegates to SimpleLogger for proper file logging
  # This maintains backward compatibility while ensuring logs go to files
  module LogHelper
    def self.log(message, level = :info)
      case level
      when :error
        Services::Logging::SimpleLogger.error(message, tagged: [:log_helper])
      when :warning
        Services::Logging::SimpleLogger.warn(message, tagged: [:log_helper])
      when :success
        Services::Logging::SimpleLogger.info("✅ #{message}", tagged: %i[log_helper success])
      when :debug
        Services::Logging::SimpleLogger.debug(message, tagged: [:log_helper])
      else
        Services::Logging::SimpleLogger.info(message, tagged: [:log_helper])
      end
    end

    def self.handles_extra_args(message, context = nil)
      return message unless context.present?

      "#{message} | WARNING EXTRA ARGS PASSED #{context.inspect}"
    end

    def self.error(message, context = nil)
      message = handles_extra_args(message, context) if context.present?

      Services::Logging::SimpleLogger.error(message, tagged: [:log_helper])
    end

    def self.warning(message, context = nil)
      message = handles_extra_args(message, context) if context.present?

      Services::Logging::SimpleLogger.warn(message, tagged: [:log_helper])
    end

    def self.success(message, context = nil)
      message = handles_extra_args(message, context) if context.present?

      Services::Logging::SimpleLogger.info("✅ #{message}", tagged: %i[log_helper success])
    end

    def self.debug(message, context = nil)
      message = handles_extra_args(message, context) if context.present?

      Services::Logging::SimpleLogger.debug(message, tagged: [:log_helper])
    end

    # Compatibility method for structured logging
    def self.info(message, metadata = {})
      Services::Logging::SimpleLogger.info(message, tagged: [:log_helper], **metadata)
    end
  end
end
