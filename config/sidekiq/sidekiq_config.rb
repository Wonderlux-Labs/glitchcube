# frozen_string_literal: true

# Comprehensive Sidekiq Configuration Strategy
#
# This module provides environment-specific Sidekiq configuration:
# - Test mode: Always run inline (no Redis dependency)
# - Development mode: Run inline by default, allow separate process with env var
# - Production mode: Always run as separate process with Redis

module SidekiqConfig
  class << self
    # Determines if Sidekiq should run inline (synchronously) for this environment
    def inline_mode?
      case environment
      when 'test'
        true # Always inline in tests
      when 'development'
        ENV['SIDEKIQ_INLINE'] != 'false' # Inline by default, override with SIDEKIQ_INLINE=false
      when 'production'
        false # Never inline in production
      else
        true # Default to inline for unknown environments
      end
    end

    # Determines if Sidekiq should be loaded and configured
    def sidekiq_enabled?
      case environment
      when 'test'
        true # Always available but inline
      when 'development'
        true # Always available
      when 'production'
        true # Always available
      else
        false # Disabled for unknown environments
      end
    end

    # Determines if Redis connection is required
    def redis_required?
      sidekiq_enabled? && !inline_mode?
    end

    # Configure Sidekiq based on environment
    def configure!
      return unless sidekiq_enabled?

      if inline_mode?
        configure_inline_mode!
      else
        configure_background_mode!
      end
    end

    # Check if Sidekiq is available and Redis is accessible (for background mode)
    def available?
      return false unless defined?(Sidekiq)
      return true if inline_mode? # No Redis check needed for inline

      redis_available?
    end

    private

    def environment
      ENV['RACK_ENV'] || 'development'
    end

    def configure_inline_mode!
      require 'sidekiq/testing'
      Sidekiq::Testing.inline!

      puts "[INFO] Sidekiq configured for inline mode - jobs will run synchronously (env: #{environment})"
    end

    def configure_background_mode!
      # Only configure Redis connection if not already configured
      unless sidekiq_redis_configured?
        redis_url = ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')

        Sidekiq.configure_server do |config|
          config.redis = { url: redis_url }
        end

        Sidekiq.configure_client do |config|
          config.redis = { url: redis_url }
        end
      end

      puts "[INFO] Sidekiq configured for background mode - jobs will run asynchronously (env: #{environment})"
    end

    def redis_available?
      require 'redis'
      redis = Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
      redis.ping == 'PONG'
    rescue StandardError => e
      puts "[WARN] Redis connection failed - Sidekiq jobs will not be processed: #{e.message}"
      false
    ensure
      redis&.quit
    end

    def sidekiq_redis_configured?
      defined?(Sidekiq) &&
        Sidekiq.respond_to?(:redis_info) &&
        !Sidekiq.redis_info.nil?
    rescue StandardError
      false
    end
  end

  # Helper module to include in classes that need to schedule jobs safely
  module JobScheduler
    def schedule_job_safely(job_class, *, delay: nil)
      return false unless SidekiqConfig.available?

      if delay
        job_class.perform_in(delay, *)
      else
        job_class.perform_async(*)
      end

      true
    rescue StandardError => e
      puts "[ERROR] Failed to schedule job #{job_class}: #{e.message}"
      false
    end
  end
end

# Auto-configure when loaded
if defined?(Rails)
  # For Rails applications
  Rails.application.config.after_initialize do
    SidekiqConfig.configure!
  end
elsif SidekiqConfig.sidekiq_enabled?
  # For non-Rails applications (like Sinatra)
  SidekiqConfig.configure!
end
