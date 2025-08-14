# frozen_string_literal: true

# Initialize the simple logger service

# Create convenient global methods for logging
module Kernel
  def log
    Services::Logging::SimpleLogger
  end
end

# Set up logger for Sinatra app (if in Sinatra context)
if defined?(configure)
  configure :development, :production, :test do
    # SimpleLogger handles its own setup - no need for explicit logger setup
  end
end

# Log application startup (defer until logger is available)
# This will be called from app.rb after all initializers are loaded
# Services::Logging::SimpleLogger.info(
#   'Cube starting up',
#   tagged: [:startup],
#   environment: Cube::Settings.rack_env,
#   version: GlitchCube.config.device.app_version
# )
