# frozen_string_literal: true

# First, load the service registry
require_relative '../../lib/core/service_registry'

# Autoload all library files using lazy loading and dependency management
# This eliminates the need for require_relative statements throughout the codebase

# Load order is important for dependencies
module Autoloader
  class << self
    def load_all
      # Phase 1: Register all service locations without loading
      register_all_services

      # Phase 2: Load only critical services needed at startup
      load_critical_services

      # Phase 3: Load other non-lazy components
      # IMPORTANT: load_base_classes MUST come before load_core
      # because ErrorHandling module is needed by HomeAssistantClient
      load_base_classes
      load_core
      load_config
      load_utilities
      load_personas
      load_tools

      # Phase 4: In test environment, load all services after tools are available
      if ENV['RACK_ENV'] == 'test'
        load_all_services_for_tests
      end

      load_jobs
      load_routes
    end

    private

    def register_all_services
      # Register all services with their dependencies
      # These will be lazy-loaded on first access

      # Logging services (no dependencies, load first)
      ServiceRegistry.register(:simple_logger, 'services/logging/simple_logger')
      ServiceRegistry.register(:logger_service, 'services/logging/logger_service',
                               dependencies: [:simple_logger])

      # System services
      ServiceRegistry.register(:error_handling_llm, 'services/system/error_handling_llm',
                               dependencies: [:logger_service])
      ServiceRegistry.register(:circuit_breaker_service, 'services/system/circuit_breaker_service',
                               dependencies: [:logger_service])
      ServiceRegistry.register(:tool_registry_service, 'services/system/tool_registry_service',
                               dependencies: [:logger_service])
      ServiceRegistry.register(:tool_executor, 'services/system/tool_executor',
                               dependencies: %i[tool_registry_service logger_service])
      ServiceRegistry.register(:entity_manager_service, 'services/system/entity_manager_service',
                               dependencies: [:logger_service])
      ServiceRegistry.register(:character_service, 'services/system/character_service',
                               dependencies: [:logger_service])
      ServiceRegistry.register(:health_push_service, 'services/system/health_push_service',
                               dependencies: [:logger_service])
      ServiceRegistry.register(:host_registration_service, 'services/system/host_registration_service',
                               dependencies: [:logger_service])
      ServiceRegistry.register(:proactive_interaction_service, 'services/system/proactive_interaction_service',
                               dependencies: %i[logger_service entity_manager_service])
      ServiceRegistry.register(:repeating_jobs_manager, 'services/system/repeating_jobs_manager',
                               dependencies: [:logger_service])
      ServiceRegistry.register(:home_assistant_webhook_service, 'services/system/home_assistant_webhook_service',
                               dependencies: [:logger_service])
      ServiceRegistry.register(:system_prompt_service, 'services/system/system_prompt_service',
                               dependencies: [:logger_service])

      # LLM services
      ServiceRegistry.register(:llm_service, 'services/llm/llm_service',
                               dependencies: %i[logger_service circuit_breaker_service])
      ServiceRegistry.register(:llm_response, 'services/llm/llm_response')

      # Memory services
      ServiceRegistry.register(:memory_recall_service, 'services/memory/memory_recall_service',
                               dependencies: [:logger_service])
      ServiceRegistry.register(:context_injection_service, 'services/memory/context_injection_service',
                               dependencies: %i[logger_service memory_recall_service])
      ServiceRegistry.register(:context_retrieval_service, 'services/memory/context_retrieval_service',
                               dependencies: [:logger_service])
      ServiceRegistry.register(:context_enrichment_service, 'services/memory/context_enrichment_service',
                               dependencies: %i[logger_service context_retrieval_service])

      # GPS services
      ServiceRegistry.register(:gps_cache_service, 'services/gps/gps_cache_service',
                               dependencies: [:logger_service])
      ServiceRegistry.register(:gps_tracking_service, 'services/gps/gps_tracking_service',
                               dependencies: %i[logger_service gps_cache_service])

      # Conversation services
      ServiceRegistry.register(:conversation_handler_service, 'services/conversation/conversation_handler_service',
                               dependencies: %i[logger_service llm_service memory_recall_service])
      ServiceRegistry.register(:conversation_session, 'services/conversation/conversation_session',
                               dependencies: [:logger_service])
      ServiceRegistry.register(:conversation_tool_handler, 'services/conversation/conversation_tool_handler',
                               dependencies: %i[logger_service tool_executor])
      ServiceRegistry.register(:conversation_error_handler, 'services/conversation/conversation_error_handler',
                               dependencies: [:logger_service])
      ServiceRegistry.register(:conversation_feedback_service, 'services/conversation/conversation_feedback_service',
                               dependencies: [:logger_service])
      ServiceRegistry.register(:conversation_side_effect_handler, 'services/conversation/conversation_side_effect_handler',
                               dependencies: [:logger_service])
      ServiceRegistry.register(:conversation_summarizer, 'services/conversation/conversation_summarizer',
                               dependencies: [:logger_service])

      # Register any other services in root services directory
      register_root_services
    end

    def register_root_services
      # Find and register any services in the root services directory
      Dir[File.join(root, 'lib', 'services', '*.rb')].each do |file|
        basename = File.basename(file, '.rb')
        service_name = basename.to_sym

        # Skip if already registered
        next if ServiceRegistry.registered_services.include?(service_name)

        # Register with basic dependency on logger
        ServiceRegistry.register(service_name, "services/#{basename}",
                                 dependencies: [:logger_service])
      end
    end

    def load_critical_services
      # Load only the services that are absolutely needed at startup
      # Everything else will be lazy-loaded on first access

      # Always load logging first
      ServiceRegistry.load(:simple_logger)
      ServiceRegistry.load(:logger_service)

      # Load error handling if configured
      return unless ENV['ENABLE_ERROR_HANDLING'] != 'false'

      ServiceRegistry.load(:error_handling_llm)

      # In test environment, we need to load dependencies before services
      # This will be handled after tools are loaded in load_all
    end

    def load_all_services_for_tests
      # Load all registered services for test environment
      # This ensures specs can reference Services::ClassName directly
      ServiceRegistry.registered_services.each do |service|
        ServiceRegistry.load(service)
      rescue StandardError => e
        # Skip services that have issues loading
        # Use stderr for warnings since logger may not be available yet
        warn "Warning: Could not load service #{service}: #{e.message}"
      end
    end

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

    # Services are now handled by ServiceRegistry with lazy loading
    # No need for explicit load_services method

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

# The namespace alias is now handled by 00_namespace_setup.rb
# which loads before this file and sets up proper constant resolution
