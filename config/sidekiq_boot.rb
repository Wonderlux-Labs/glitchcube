# frozen_string_literal: true

# Sidekiq boot file - ensures proper environment setup for workers
# This file is loaded by Sidekiq to initialize the worker environment

# Set environment
ENV['RACK_ENV'] ||= 'development'

# Load environment variables in correct order
# Priority (lowest to highest): .env.defaults < .env.{environment} < .env < ENV vars
# Dotenv.load uses reverse order - first file wins, so we list from most to least specific
require 'dotenv'
Dotenv.load(
  '.env', # User overrides (highest file priority)
  ".env.#{ENV.fetch('RACK_ENV', nil)}", # Environment-specific settings
  '.env.defaults' # Base defaults (lowest file priority)
)
# Manually set ENV vars always have highest priority (not overwritten by Dotenv)

# CRITICAL: Load and configure database BEFORE loading app
# This ensures Sidekiq uses the correct database configuration
require_relative 'database_config'

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

# Now load the main application
require_relative '../app'

# Load Sidekiq configuration
require_relative 'sidekiq'

puts '✅ Sidekiq environment loaded successfully'
