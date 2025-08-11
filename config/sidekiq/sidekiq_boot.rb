# frozen_string_literal: true

# Sidekiq boot file - ensures proper environment setup for workers
# This file is loaded by Sidekiq to initialize the worker environment

# CRITICAL: Load and configure database BEFORE loading app
# This ensures Sidekiq uses the correct database configuration

# Load the database configuration module first
require_relative '../database_config'

# Configure database with our centralized config
puts '🗄️  Configuring Sidekiq database...'
puts "   ENV['RACK_ENV']: #{ENV.fetch('RACK_ENV', nil)}"
puts "   DatabaseConfig.environment: #{DatabaseConfig.environment}"

configure_database!

config = DatabaseConfig.configuration
puts "   Environment: #{DatabaseConfig.environment}"
puts "   Host: #{config['host']}"
puts "   Database: #{config['database']}"
puts "   Username: #{config['username']}"
puts "   Pool: #{config['pool']}"

# Now load the main application - this loads all the autoloader and services
require_relative '../../app'

# IMPORTANT: Only load Sidekiq configuration AFTER the app is loaded
# This ensures all Services and modules are available for the middleware
require_relative 'sidekiq'

puts '✅ Sidekiq environment loaded successfully'
