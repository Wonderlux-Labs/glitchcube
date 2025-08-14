# frozen_string_literal: true

# Autoload all library files using Zeitwerk for services and manual loading for other components
# Services are now handled by Zeitwerk (see 01_zeitwerk.rb)

module Autoloader
  class << self
    def load_all
      # Services are now auto-loaded by Zeitwerk
      # Only need to manually load components that don't follow Zeitwerk conventions

      load_base_classes
      load_core
      load_config
      load_utilities
      load_personas
      load_tools
      load_jobs
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
      # Helpers and utilities
      Dir[File.join(root, 'lib', 'helpers', '*.rb')].each { |f| require f }
      Dir[File.join(root, 'lib', 'utils', '*.rb')].each { |f| require f }
    end

    def load_base_classes
      # ErrorHandling module must load first as many classes include it
      require_if_exists 'lib/modules/error_handling'

      # Then load other modules
      Dir[File.join(root, 'lib', 'modules', '*.rb')].each do |f|
        require f unless f.include?('error_handling')
      end

      # Base tool class before specific tools
      require_if_exists 'lib/tools/base_tool'
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
      # Base tool is already loaded, load the rest
      Dir[File.join(root, 'lib', 'tools', '*.rb')].each do |f|
        require f unless f.include?('base_tool')
      end
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

# Load everything when this initializer runs
Autoloader.load_all
