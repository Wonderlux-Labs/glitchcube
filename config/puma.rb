# frozen_string_literal: true

require_relative '../lib/cube/settings'

# Puma configuration for Glitch Cube
# This file is used when running: bundle exec puma -C config/puma.rb

# Threads configuration
# min_threads_count and max_threads_count set the minimum and maximum
# number of threads to use to answer requests
threads_min = Integer(ENV.fetch('PUMA_MIN_THREADS', '1'))
threads_max = Integer(ENV.fetch('PUMA_MAX_THREADS', '5'))
threads threads_min, threads_max

# Workers configuration (processes)
# For single-user art installation, we don't need multiple workers
# Set PUMA_WORKERS=2 or more for production deployments with multiple users
worker_count = Integer(ENV.fetch('PUMA_WORKERS', '1'))
workers worker_count

# Port configuration
# Use Foreman's PORT if set, otherwise use default port
configured_port = ENV['PORT']&.to_i || Cube::Settings.port
port configured_port

# Environment
environment Cube::Settings.rack_env

# Bind to both localhost and 0.0.0.0 for flexibility
# Use 0.0.0.0 to allow external connections (needed for Docker/network access)
if ENV['BIND_ALL'] == 'true' || Cube::Settings.docker_deployment?
  bind "tcp://0.0.0.0:#{configured_port}"
else
  bind "tcp://127.0.0.1:#{configured_port}"
end

# Logging
log_path = if Cube::Settings.test?
  'logs/test'
else
  'logs'
end

if Cube::Settings.development?
  # Verbose logging in development
  stdout_redirect "#{log_path}/puma.stdout.log", "#{log_path}/puma.stderr.log", true
elsif !Cube::Settings.test?
  # Production logging (skip in test to reduce noise)
  stdout_redirect "#{log_path}/puma.stdout.log", "#{log_path}/puma.stderr.log"
end

# Allow puma to be restarted by the deployment process
# This creates a control socket for sending commands to Puma
if ENV['PUMA_CONTROL_URL']
  activate_control_app ENV['PUMA_CONTROL_URL']
elsif Cube::Settings.development?
  activate_control_app 'tcp://127.0.0.1:9293'
end

# Preload the application for better performance (production only)
# This loads the app before forking workers, saving memory
if worker_count > 1
  preload_app!
  
  before_fork do
    # Disconnect from database before forking
    # This prevents connection pool issues
    require_relative '../config/persistence'
    if defined?(ActiveRecord::Base)
      ActiveRecord::Base.connection_pool.disconnect!
    end
  end

  on_worker_boot do
    # Reconnect to database in each worker
    if defined?(ActiveRecord::Base)
      ActiveRecord::Base.establish_connection
    end
  end
end

# State management
# Store Puma's state for restart/stop commands
state_path 'tmp/pids/puma.state'

# PID file for process management
pidfile 'tmp/pids/puma.pid'

# Restart command (used by systemd, deployment scripts)
restart_command 'bundle exec puma'

# Performance tuning for single-user art installation
# Lower timeouts since we have controlled environment
worker_timeout 30 if worker_count > 1
worker_shutdown_timeout 10 if worker_count > 1

# Request logging format - always log for debugging
log_requests true

# Tag for logging (useful when running multiple apps)
tag 'glitchcube'

# Plugin for better systemd integration (if available)
begin
  plugin :systemd
rescue LoadError
  # Systemd plugin not available, that's okay
end

# Create necessary directories
dirs_to_create = ['tmp/pids', 'logs']
dirs_to_create << 'logs/test' if Cube::Settings.test?

dirs_to_create.each do |dir|
  FileUtils.mkdir_p(dir) unless File.directory?(dir)
end

puts "🟢 Puma configured:"
puts "  Environment: #{Cube::Settings.rack_env}"
puts "  Port: #{Cube::Settings.port}"
puts "  Workers: #{worker_count}"
puts "  Threads: #{threads_min}-#{threads_max}"
puts "  Binding: #{ENV['BIND_ALL'] == 'true' || Cube::Settings.docker_deployment? ? '0.0.0.0' : '127.0.0.1'}"
puts "  Database: #{Cube::Settings.database_type}"