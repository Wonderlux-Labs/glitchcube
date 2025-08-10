# frozen_string_literal: true

# Autoload all library files in the correct order
# This eliminates the need for require_relative statements throughout the codebase

# Load order is important for dependencies
module Autoloader
  class << self
    def load_all
      # 1. Core dependencies first
      load_core

      # 2. Configuration and constants
      load_config

      # 3. Utilities and helpers
      load_utilities

      # 4. Base classes and modules
      load_base_classes

      # 5. Personas (base class first, then specific personas)
      load_personas

      # 6. Tools (must be before services since ToolExecutor references them)
      load_tools

      # 7. Services (with subdirectories)
      load_services

      # 8. Jobs and workers (may depend on services)
      load_jobs

      # 9. Routes
      load_routes
    end

    private

    def load_core
      # Core infrastructure that other files depend on
      require_if_exists 'lib/core/circuit_breaker'
      require_if_exists 'lib/core/error_handler_integration'
      # HomeAssistantClient needs ErrorHandling module loaded first
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

      # Now load HomeAssistantClient after ErrorHandling module is available
      require_if_exists 'lib/core/home_assistant_client'

      # Base tool class before specific tools
      require_if_exists 'lib/tools/base_tool'
    end

    def load_services
      # Services with proper subdirectory loading
      # Load logging services first as many others depend on them
      Dir[File.join(root, 'lib', 'services', 'logging', '*.rb')].each { |f| require f }

      # Then system services
      Dir[File.join(root, 'lib', 'services', 'system', '*.rb')].each { |f| require f }

      # Then other service subdirectories
      %w[llm memory gps conversation].each do |subdir|
        Dir[File.join(root, 'lib', 'services', subdir, '*.rb')].each { |f| require f }
      end

      # Finally any services in the root services directory
      Dir[File.join(root, 'lib', 'services', '*.rb')].each { |f| require f }
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
