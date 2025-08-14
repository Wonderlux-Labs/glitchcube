# frozen_string_literal: true

module Helpers
  # LogHelper delegates to SimpleLogger for proper file logging
  # This maintains backward compatibility while ensuring logs go to files
  module LogHelper
    def self.log(message, level = :info)
      # Map LogHelper levels to SimpleLogger methods
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

    def self.error(message)
      Services::Logging::SimpleLogger.error(message, tagged: [:log_helper])
    end

    def self.warning(message)
      Services::Logging::SimpleLogger.warn(message, tagged: [:log_helper])
    end

    def self.success(message)
      Services::Logging::SimpleLogger.info("✅ #{message}", tagged: %i[log_helper success])
    end

    def self.debug(message)
      Services::Logging::SimpleLogger.debug(message, tagged: [:log_helper])
    end

    # Compatibility method for structured logging
    def self.info(message, metadata = {})
      Services::Logging::SimpleLogger.info(message, tagged: [:log_helper], **metadata)
    end
  end
end
