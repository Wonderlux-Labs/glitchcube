# frozen_string_literal: true

# Centralized environment loader for GlitchCube

# Set default environment if not specified
ENV['RACK_ENV'] ||= 'development'

# Load environment variables BEFORE anything else
# Priority (lowest to highest): .env.defaults < .env.{environment} < .env < ENV vars
# Dotenv.load uses reverse order - first file wins, so list from most to least specific

begin
  require 'dotenv'

  if ENV['RACK_ENV'] == 'test'
    Dotenv.load('.env', '.env.test', '.env.defaults')
  else
    env_file = ".env.#{ENV['RACK_ENV'] || 'development'}"
    Dotenv.load('.env', env_file, '.env.defaults')
  end
rescue LoadError
  puts '[WARNING] Dotenv gem not found, env files will not be loaded'
end
