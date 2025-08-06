# frozen_string_literal: true

# Initialize the unified logger service
require_relative '../../lib/services/unified_logger_service'

# Set up unified logging
Services::UnifiedLoggerService.setup!

# Create convenient global methods for logging
module Kernel
  def log
    Services::UnifiedLoggerService
  end
end

# Set up logger for Sinatra app
configure :development, :production, :test do
  # Use the unified logger as the main logger
  set :logger, Services::UnifiedLoggerService.logger if Services::UnifiedLoggerService.logger
end

# Log application startup
Services::UnifiedLoggerService.system_event(
  event: 'app_startup',
  environment: Cube::Settings.rack_env,
  version: GlitchCube.config.device.app_version
)