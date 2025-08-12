# frozen_string_literal: true

# LogHelper delegates to SimpleLogger for proper file logging
# This maintains backward compatibility while ensuring logs go to files
module LogHelper
  def self.log(message, level = :info)
    # Map LogHelper levels to SimpleLogger methods
    case level
    when :error
      Services::SimpleLogger.error(message, tagged: [:log_helper])
    when :warning
      Services::SimpleLogger.warn(message, tagged: [:log_helper])
    when :success
      Services::SimpleLogger.info("✅ #{message}", tagged: %i[log_helper success])
    when :debug
      Services::SimpleLogger.debug(message, tagged: [:log_helper])
    else
      Services::SimpleLogger.info(message, tagged: [:log_helper])
    end
  end

  def self.error(message)
    Services::SimpleLogger.error(message, tagged: [:log_helper])
  end

  def self.warning(message)
    Services::SimpleLogger.warn(message, tagged: [:log_helper])
  end

  def self.success(message)
    Services::SimpleLogger.info("✅ #{message}", tagged: %i[log_helper success])
  end

  def self.debug(message)
    Services::SimpleLogger.debug(message, tagged: [:log_helper])
  end

  # Compatibility method for structured logging
  def self.info(message, metadata = {})
    Services::SimpleLogger.info(message, tagged: [:log_helper], **metadata)
  end
end
