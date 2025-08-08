# frozen_string_literal: true

# Centralized environment loader for GlitchCube

# Load environment variables BEFORE anything else
# Priority (lowest to highest): .env.defaults < .env.{environment} < .env < ENV vars
# Dotenv.load uses reverse order - first file wins, so list from most to least specific

if defined?(Dotenv).nil?
  begin
    require 'dotenv'
  rescue LoadError
    puts '[WARNING] Dotenv gem not found, env files will not be loaded'
  end
end

if defined?(Dotenv)
  if ENV['RACK_ENV'] == 'test'
    Dotenv.load('.env', '.env.test', '.env.defaults')
  else
    env_file = ".env.#{ENV['RACK_ENV'] || 'development'}"
    Dotenv.load('.env', env_file, '.env.defaults')
  end
end

puts "[DEBUG] ENV['HA_URL'] at boot: #{ENV['HA_URL'].inspect}"
puts "[DEBUG] ENV['HOME_ASSISTANT_URL'] at boot: #{ENV['HOME_ASSISTANT_URL'].inspect}"
