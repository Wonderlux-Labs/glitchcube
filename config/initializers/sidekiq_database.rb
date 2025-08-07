# frozen_string_literal: true

# Ensure Sidekiq workers have proper database configuration
# This file is loaded when Sidekiq starts up

if defined?(Sidekiq) && Sidekiq.server?
  require_relative '../database_config'

  # Configure database for Sidekiq workers
  configure_database!

  puts '🗄️  Sidekiq database configured:'
  puts "   Environment: #{DatabaseConfig.environment}"
  puts "   Host: #{DatabaseConfig.configuration['host']}"
  puts "   Database: #{DatabaseConfig.configuration['database']}"
  puts "   Pool: #{DatabaseConfig.configuration['pool']}"
end
