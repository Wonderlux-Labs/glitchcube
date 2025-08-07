# frozen_string_literal: true

# Sidekiq boot file - ensures proper environment setup for workers
# This file is loaded by Sidekiq to initialize the worker environment

# Set environment
ENV['RACK_ENV'] ||= 'development'

# Load environment variables
require 'dotenv'
Dotenv.load(".env.#{ENV['RACK_ENV']}", '.env.defaults', '.env')

# CRITICAL: Load and configure database BEFORE loading app
# This ensures Sidekiq uses the correct database configuration
require_relative 'database_config'

# Configure database with our centralized config
puts "🗄️  Configuring Sidekiq database..."
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

puts "✅ Sidekiq environment loaded successfully"