# frozen_string_literal: true

# ServiceRegistry manages lazy loading of services with dependency resolution
# This eliminates the need for manual require statements and handles load order
class ServiceRegistry
  class CircularDependencyError < StandardError; end
  class ServiceNotFoundError < StandardError; end

  class << self
    def initialize_registry
      @services = {}
      @loaded = {}
      @loading = Set.new
      @mutex = Mutex.new
    end

    # Register a service with its path and dependencies
    # @param name [Symbol] Service name
    # @param path [String] Path to service file (relative to lib/)
    # @param dependencies [Array<Symbol>] List of service dependencies
    def register(name, path, dependencies: [])
      @mutex.synchronize do
        @services[name.to_sym] = {
          path: path,
          dependencies: Array(dependencies).map(&:to_sym),
          loaded: false
        }
      end
    end

    # Load a service and its dependencies
    # @param name [Symbol] Service name to load
    # @raise [CircularDependencyError] if circular dependency detected
    # @raise [ServiceNotFoundError] if service not registered
    def load(name)
      name = name.to_sym

      @mutex.synchronize do
        # Already loaded?
        return true if @loaded[name]

        # Check for circular dependencies
        if @loading.include?(name)
          raise CircularDependencyError, "Circular dependency detected for #{name}"
        end

        # Get service info
        service = @services[name]
        unless service
          caller_info = caller(1, 1).first
          raise ServiceNotFoundError, "Service #{name} not registered (called from: #{caller_info})"
        end

        # Mark as loading to detect circular deps
        @loading.add(name)

        begin
          # Load dependencies first (recursive)
          service[:dependencies].each do |dep|
            load_without_lock(dep)
          end

          # Construct full path
          full_path = if service[:path].start_with?('/')
                        service[:path]
                      else
                        File.join(root_path, 'lib', service[:path])
                      end

          # Add .rb extension if not present
          full_path += '.rb' unless full_path.end_with?('.rb')

          # Load the service file
          unless File.exist?(full_path)
            caller_info = caller(1, 1).first
            raise ServiceNotFoundError, "Service file not found: #{full_path} (called from: #{caller_info})"
          end

          require full_path
          @loaded[name] = true
          true
        ensure
          @loading.delete(name)
        end
      end
    end

    # Check if a service is loaded
    def loaded?(name)
      @loaded[name.to_sym] || false
    end

    # Get all registered services
    def registered_services
      @services.keys
    end

    # Get dependencies for a service
    def dependencies_for(name)
      service = @services[name.to_sym]
      service ? service[:dependencies] : []
    end

    # Clear the registry (useful for testing)
    def clear!
      @mutex.synchronize do
        @services = {}
        @loaded = {}
        @loading = Set.new
      end
    end

    private

    # Internal load without mutex lock (for recursive calls)
    def load_without_lock(name)
      name = name.to_sym
      return true if @loaded[name]

      if @loading.include?(name)
        raise CircularDependencyError, "Circular dependency detected for #{name}"
      end

      service = @services[name]
      unless service
        caller_info = caller(1, 1).first
        raise ServiceNotFoundError, "Service #{name} not registered (called from: #{caller_info})"
      end

      @loading.add(name)

      begin
        service[:dependencies].each do |dep|
          load_without_lock(dep)
        end

        full_path = if service[:path].start_with?('/')
                      service[:path]
                    else
                      File.join(root_path, 'lib', service[:path])
                    end

        full_path += '.rb' unless full_path.end_with?('.rb')

        unless File.exist?(full_path)
          caller_info = caller(1, 1).first
          raise ServiceNotFoundError, "Service file not found: #{full_path} (called from: #{caller_info})"
        end

        require full_path
        @loaded[name] = true
        true
      ensure
        @loading.delete(name)
      end
    end

    def root_path
      @root_path ||= File.expand_path('../..', __dir__)
    end
  end

  # Initialize the registry
  initialize_registry
end

# Helper method for services to declare their dependencies
module ServiceDependencies
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def depends_on(*services)
      services.each do |service|
        ServiceRegistry.load(service)
      end
    end
  end
end
