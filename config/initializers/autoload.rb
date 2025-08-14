# frozen_string_literal: true

# Autoload all library files using Zeitwerk for services and manual loading for other components
# Services are now handled by Zeitwerk (see 01_zeitwerk.rb)

module Autoloader
  class << self
    def load_all
      # Services are now auto-loaded by Zeitwerk
      # Only need to manually load components that don't follow Zeitwerk conventions
      # Note: Routes will be loaded after Zeitwerk setup completes to ensure modules are available

      load_base_classes
      load_core
      load_config
      load_utilities
      load_personas
      load_tools
      load_jobs
      # load_routes - moved to separate call after Zeitwerk setup
    end

    def load_routes_after_zeitwerk
      load_routes
    end

    private

    def load_core
      # Core infrastructure that other files depend on
      require_if_exists 'lib/core/circuit_breaker'
      require_if_exists 'lib/core/error_handler_integration'
      require_if_exists 'lib/core/home_assistant_client'
    end

    def load_config
      # Cube settings and schemas
      Dir[File.join(root, 'lib', 'cube', '*.rb')].each { |f| require f }
      Dir[File.join(root, 'lib', 'schemas', '*.rb')].each { |f| require f }
    end

    def load_utilities
      # Helpers only - utils are now handled by Zeitwerk
      Dir[File.join(root, 'lib', 'helpers', '*.rb')].each { |f| require f }
    end

    def load_base_classes
      # Modules are now handled by Zeitwerk autoloading
      # No manual loading needed
    end

    def load_jobs
      Dir[File.join(root, 'lib', 'jobs', '*.rb')].each { |f| require f }
    end

    def load_personas
      # Load base persona first
      require_if_exists 'lib/personas/base_persona'

      # Then load specific personas (excluding base and factory)
      Dir[File.join(root, 'lib', 'personas', '*.rb')].each do |f|
        next if f.include?('base_persona') || f.include?('persona_factory')

        require f
      end

      # Finally load persona factory after all personas are available
      require_if_exists 'lib/personas/persona_factory'
    end

    def load_tools
      # Tools are now handled by Zeitwerk - no manual loading needed
    end

    def load_routes
      # Load all routes including subdirectories
      Dir[File.join(root, 'lib', 'routes', '**', '*.rb')].each { |f| require f }
    end

    def require_if_exists(path)
      full_path = File.join(root, path)
      require full_path if File.exist?("#{full_path}.rb")
    end

    def root
      @root ||= File.expand_path('../..', __dir__)
    end
  end
end

# Load everything except routes when this initializer runs
Autoloader.load_all

# Now load routes after Zeitwerk modules are available
Autoloader.load_routes_after_zeitwerk

# Create backward compatibility aliases after Zeitwerk loading
unless defined?(ErrorHandling)
  Object.const_set(:ErrorHandling, Modules::ErrorHandling)
end

unless defined?(ConversationModule)
  Object.const_set(:ConversationModule, Modules::ConversationModule)
end
