# frozen_string_literal: true

# Centralized database configuration
# This file provides consistent database configuration across all environments
# and components (Sinatra, Sidekiq, Rake tasks, etc.)

require 'erb'
require 'yaml'
require 'uri'

module DatabaseConfig
  class << self
    # Get database configuration for the current environment
    # Prioritizes DATABASE_URL if set (for CI), otherwise uses database.yml with defaults
    def configuration
      @configuration ||= load_configuration
    end

    # Get the database URL for the current environment
    def database_url
      @database_url ||= build_database_url
    end

    # Get the current environment
    def environment
      ENV['RACK_ENV'] || ENV['RAILS_ENV'] || 'development'
    end

    # Check if we're in CI
    def ci?
      ENV['CI'] == 'true'
    end

    # Check if we're in test
    def test?
      environment == 'test'
    end

    # Check if we're in production
    def production?
      environment == 'production'
    end

    private

    def load_configuration
      # In CI or if DATABASE_URL is explicitly set, use it
      if ENV['DATABASE_URL'] && !ENV['DATABASE_URL'].empty?
        parse_database_url(ENV['DATABASE_URL'])
      else
        # Load from database.yml with defaults
        load_from_yaml
      end
    end

    def load_from_yaml
      config_file = File.expand_path('../database.yml', __FILE__)
      
      if File.exist?(config_file)
        # Load and parse the YAML with ERB support
        yaml_content = File.read(config_file)
        erb_result = ERB.new(yaml_content).result
        config = YAML.safe_load(erb_result, aliases: true)
        
        # Get config for current environment
        env_config = config[environment] || config['default']
        
        # Apply defaults if not in CI
        apply_defaults(env_config)
      else
        # Fallback to hardcoded defaults if no database.yml
        default_configuration
      end
    end

    def apply_defaults(config)
      config ||= {}
      
      # Set sensible defaults for local development/test
      config['adapter'] ||= 'postgresql'
      config['host'] ||= ENV.fetch('DATABASE_HOST', 'localhost')
      config['port'] ||= ENV.fetch('DATABASE_PORT', 5432).to_i
      config['username'] ||= ENV.fetch('DATABASE_USER', 'postgres')
      config['password'] ||= ENV.fetch('DATABASE_PASSWORD', 'postgres')
      config['database'] ||= "glitchcube_#{environment}"
      config['encoding'] ||= 'unicode'
      config['pool'] ||= ENV.fetch('DB_POOL_SIZE', 5).to_i
      
      # Handle PostGIS adapter
      config['adapter'] = 'postgresql' if config['adapter'] == 'postgis'
      
      config
    end

    def default_configuration
      {
        'adapter' => 'postgresql',
        'host' => 'localhost',
        'port' => 5432,
        'username' => 'postgres',
        'password' => 'postgres',
        'database' => "glitchcube_#{environment}",
        'encoding' => 'unicode',
        'pool' => 5
      }
    end

    def parse_database_url(url)
      uri = URI.parse(url)
      
      # Extract components from URL
      config = {
        'adapter' => uri.scheme == 'postgres' ? 'postgresql' : uri.scheme,
        'host' => uri.host || 'localhost',
        'port' => uri.port || 5432,
        'database' => uri.path[1..-1], # Remove leading slash
        'username' => uri.user || 'postgres',
        'password' => uri.password || 'postgres'
      }
      
      # Add query parameters if present
      if uri.query
        params = URI.decode_www_form(uri.query).to_h
        config['pool'] = params['pool'].to_i if params['pool']
        config['encoding'] = params['encoding'] if params['encoding']
      end
      
      config['pool'] ||= 5
      config['encoding'] ||= 'unicode'
      
      config
    end

    def build_database_url
      config = configuration
      
      # Build URL from configuration
      adapter = config['adapter'] == 'postgresql' ? 'postgres' : config['adapter']
      username = config['username']
      password = config['password']
      host = config['host']
      port = config['port']
      database = config['database']
      
      url = "#{adapter}://"
      
      if username && !username.empty?
        url += username
        url += ":#{password}" if password && !password.empty?
        url += "@"
      end
      
      url += "#{host}:#{port}/#{database}"
      
      # Add query parameters
      params = []
      params << "pool=#{config['pool']}" if config['pool']
      params << "encoding=#{config['encoding']}" if config['encoding']
      
      url += "?#{params.join('&')}" unless params.empty?
      
      url
    end
  end
end

# Set DATABASE_URL if not already set (for components that expect it)
ENV['DATABASE_URL'] ||= DatabaseConfig.database_url

# Provide a method to configure ActiveRecord
def configure_database!
  require 'active_record'
  
  config = DatabaseConfig.configuration
  
  # Special handling for PostGIS
  if config['adapter'] == 'postgis'
    require 'activerecord-postgis-adapter'
  end
  
  ActiveRecord::Base.establish_connection(config)
  
  # Enable query logging in development
  if DatabaseConfig.environment == 'development'
    ActiveRecord::Base.logger = Logger.new(STDOUT)
    ActiveRecord::Base.logger.level = Logger::INFO
  end
end