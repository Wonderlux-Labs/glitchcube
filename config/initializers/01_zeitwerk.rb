# frozen_string_literal: true

# Zeitwerk auto-loading configuration
# Standard Ruby auto-loading configuration

require 'zeitwerk'

# Set up the main autoloader
loader = Zeitwerk::Loader.new

# Add lib directory to the load path
loader.push_dir(File.expand_path('../../lib', __dir__))

# Ignore directories that need manual loading due to complex dependencies
# modules and utils are now Zeitwerk-compatible
loader.ignore(File.expand_path('../../lib/routes', __dir__))
loader.ignore(File.expand_path('../../lib/personas', __dir__))
loader.ignore(File.expand_path('../../lib/helpers', __dir__))
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

# Set up the loader with eager loading for both development and production
# This ensures we catch autoloading issues early in development
# Skip eager loading for rake tasks to avoid issues during migrations
if ENV['RACK_ENV'] == 'production'
  loader.enable_reloading if ENV['ENABLE_RELOADING'] == 'true'
else
  # Development: enable reloading and eager loading to catch issues early
  loader.enable_reloading
end
loader.setup
loader.eager_load unless defined?(Rake)

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

# Ensure top-level modules exist for Zeitwerk autoloading
unless defined?(Modules)
  module Modules; end
end

unless defined?(Utils)
  module Utils; end
end

# Store the loader for potential reloading in development
$zeitwerk_loader = loader
