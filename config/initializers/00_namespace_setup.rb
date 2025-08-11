# frozen_string_literal: true

# This file sets up namespaces BEFORE any code loading happens
# It solves the constant resolution issues by ensuring all modules exist
# before any code tries to reference them

# Define root module
module GlitchCube
  # Pre-define all nested modules to avoid constant resolution issues
  module Routes; end
  module Services; end
  module Jobs; end
  module Personas; end
  module Tools; end
  module Helpers; end
  module Modules; end
  module Schemas; end
  module Core; end

  # Set up const_missing hook to handle Services references
  # This allows routes to use Services instead of ::Services
  def self.const_missing(name)
    case name
    when :Services
      # Return global Services module when referenced from within GlitchCube
      return ::Services if defined?(::Services)

      # If Services isn't loaded yet, trigger lazy loading
      ServiceRegistry.load(:services) if defined?(ServiceRegistry)
      return ::Services if defined?(::Services)
    end

    # Fall back to standard Ruby behavior
    super
  end

  # Thread-safe constant resolution tracking
  @const_resolution_mutex = Mutex.new
  @const_resolution_active = false

  def self.safe_const_missing(name)
    @const_resolution_mutex.synchronize do
      return if @const_resolution_active

      @const_resolution_active = true

      begin
        const_missing(name)
      ensure
        @const_resolution_active = false
      end
    end
  end
end

# Define global modules if they don't exist
unless defined?(Services)
  module Services
    def self.const_missing(name)
      # Check if constant was already loaded by another thread
      return const_get(name) if const_defined?(name)

      # Try to load the service via ServiceRegistry
      service_name = name.to_s.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym

      if defined?(ServiceRegistry) && ServiceRegistry.registered_services.include?(service_name)
        ServiceRegistry.load(service_name)
        # After loading, the constant should exist
        if const_defined?(name)
          return const_get(name)
        end
      end

      super
    end
  end
end
module Utils; end unless defined?(Utils)

# Create alias for Services within GlitchCube namespace
# This allows both GlitchCube::Services and Services to work
module GlitchCube
  # Remove existing constant if it exists to avoid warnings
  remove_const(:Services) if const_defined?(:Services, false)

  # Create reference to global Services
  Services = ::Services
end
