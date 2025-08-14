# frozen_string_literal: true

# Zeitwerk auto-loading configuration
# Standard Ruby auto-loading configuration

require 'zeitwerk'

# Set up the main autoloader
loader = Zeitwerk::Loader.new

# Add lib directory to the load path
loader.push_dir(File.expand_path('../../lib', __dir__))

# Ignore directories that should not be autoloaded by Zeitwerk
# These are manually loaded by the autoloader
loader.ignore(File.expand_path('../../lib/routes', __dir__))
loader.ignore(File.expand_path('../../lib/personas', __dir__))
loader.ignore(File.expand_path('../../lib/tools', __dir__))
loader.ignore(File.expand_path('../../lib/jobs', __dir__))
loader.ignore(File.expand_path('../../lib/modules', __dir__))
loader.ignore(File.expand_path('../../lib/helpers', __dir__))
loader.ignore(File.expand_path('../../lib/utils', __dir__))
loader.ignore(File.expand_path('../../lib/core', __dir__))
loader.ignore(File.expand_path('../../lib/cube', __dir__))
loader.ignore(File.expand_path('../../lib/schemas', __dir__))

# Configure module naming for our directory structure
# This maps directory paths to module namespaces

# Services directory maps to Services module
loader.inflector.inflect(
  'llm_service' => 'LLMService',
  'llm_response' => 'LLMResponse',
  'tts_service' => 'TTSService',
  'gps_tracking_service' => 'GPSTrackingService'
)

# Set up the loader with eager loading for production
if ENV['RACK_ENV'] == 'production'
  loader.enable_reloading if ENV['ENABLE_RELOADING'] == 'true'
  loader.setup
  loader.eager_load
else
  # Development: enable reloading and setup lazy loading
  loader.enable_reloading
  loader.setup
end

# For backwards compatibility, ensure Services module exists globally
# This allows existing code using ::Services to continue working
unless defined?(Services)
  Object.const_set(:Services, Module.new)
end

# Make sure GlitchCube modules are available
unless defined?(GlitchCube)
  module GlitchCube
    module Routes; end
    module Jobs; end
    module Personas; end
    module Tools; end
    module Helpers; end
    module Modules; end
    module Schemas; end
    module Core; end
  end
end

# Store the loader for potential reloading in development
$zeitwerk_loader = loader
