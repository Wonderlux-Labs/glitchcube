# frozen_string_literal: true

# Initialize the simple logger service

# Create convenient global methods for logging
module Kernel
  def log
    Services::SimpleLogger
  end
end

# Set up logger for Sinatra app
configure :development, :production, :test do
  # SimpleLogger handles its own setup - no need for explicit logger setup
end

# Log application startup
Services::SimpleLogger.info(
  'Cube starting up',
  tagged: [:startup],
  environment: Cube::Settings.rack_env,
  version: GlitchCube.config.device.app_version
)
