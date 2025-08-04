# frozen_string_literal: true

# Basic manager for controlling repeating background jobs
module RepeatingJobsManager
  extend self

  # Enable a specific service
  def enable_service(service_name)
    validate_service!(service_name)

    redis.setex("repeating_jobs:#{service_name}:enabled", 30 * 24 * 60 * 60, 'true') # 30 days
    puts "✅ Enabled #{service_name} service"

    service_name
  end

  # Disable a specific service
  def disable_service(service_name)
    validate_service!(service_name)

    redis.setex("repeating_jobs:#{service_name}:enabled", 30 * 24 * 60 * 60, 'false') # 30 days
    puts "❌ Disabled #{service_name} service"

    service_name
  end

  # Check if a service is enabled
  def service_enabled?(service_name)
    validate_service!(service_name)

    enabled = redis.get("repeating_jobs:#{service_name}:enabled")
    enabled.nil? || enabled == 'true'
  end

  # List all available services
  def list_services
    RepeatingJobsHandler::SERVICES.keys
  end

  private

  def redis
    @redis ||= GlitchCube.config.redis_connection || Redis.new(url: 'redis://localhost:6379/0')
  end

  def validate_service!(service_name)
    service_name = service_name.to_sym if service_name.is_a?(String)

    return if RepeatingJobsHandler::SERVICES.key?(service_name)

    available = RepeatingJobsHandler::SERVICES.keys.join(', ')
    raise ArgumentError, "Unknown service: #{service_name}. Available: #{available}"
  end
end
