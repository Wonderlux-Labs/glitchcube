# frozen_string_literal: true

# Zeitwerk auto-loading configuration
# Standard Ruby auto-loading configuration

require 'zeitwerk'

# Set up the main autoloader
loader = Zeitwerk::Loader.new

# Add lib directory to the load path (no namespace)
loader.push_dir(File.expand_path('../../lib', __dir__))

# All files now fully autoloaded - no more ignores needed!
# Routes: ✅ Working with parent modules
# Core: ✅ Fixed namespacing
# Personas: ⏳ Phase 2 - will remove manual loading from persona_factory.rb

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

# Services module is now properly inferred by Zeitwerk from directory structure - no explicit definition needed

# Store the loader for potential reloading in development
$zeitwerk_loader = loader
