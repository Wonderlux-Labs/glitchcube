# frozen_string_literal: true

require 'httparty'
require 'redis'
require_relative '../home_assistant_client'

module Services
  class HealthPushService
    include HTTParty

    def initialize
      @uptime_kuma_url = GlitchCube.config.monitoring.uptime_kuma_push_url
      @home_assistant_client = HomeAssistantClient.new
    end

    # Push health status to Uptime Kuma
    # Primary: Reads from Home Assistant sensor.health_monitoring
    # Fallback: Generates status from local Sinatra health when HA is down
    def push_health_status
      # First, check our own health
      sinatra_health = check_sinatra_health

      # Try to get HA health data
      ha_available = false
      health_message = nil

      begin
        health_data = fetch_health_monitoring_data
        if health_data && health_data != 'Unable to fetch health monitoring data'
          ha_available = true
          health_message = health_data
        end
      rescue StandardError
        # HA is down, we'll use fallback
      end

      # If HA is down, generate our own health message
      health_message = generate_fallback_health_message(sinatra_health) unless ha_available

      # Push to Uptime Kuma if configured
      if @uptime_kuma_url && !@uptime_kuma_url.empty?
        # Determine overall status
        # We're up if Sinatra is healthy, regardless of HA status
        status = sinatra_health[:healthy] ? 'up' : 'down'

        push_to_uptime_kuma(health_message, status)
      else
        # Just return the health data if no Uptime Kuma URL configured
        {
          status: ha_available ? 'ok' : 'degraded',
          message: health_message,
          ha_available: ha_available,
          sinatra_health: sinatra_health
        }
      end
    rescue StandardError => e
      # Even on error, we're technically "up" if this endpoint responds
      {
        status: 'error',
        message: "Health check error: #{e.message}",
        ha_available: false
      }
    end

    private

    def fetch_health_monitoring_data
      health_data = @home_assistant_client.state('sensor.health_monitoring')

      if health_data && health_data['state']
        health_data['state']
      else
        'Unable to fetch health monitoring data'
      end
    end

    def push_to_uptime_kuma(health_message, status = 'up')
      response = self.class.get(
        @uptime_kuma_url,
        query: {
          status: status,
          msg: health_message,
          ping: status == 'up' ? 1 : 0
        },
        timeout: 5
      )

      {
        status: 'pushed',
        message: health_message,
        uptime_kuma_response: response.code,
        uptime_kuma_status: status
      }
    end

    def check_sinatra_health
      # Check basic Sinatra app health
      healthy = true
      issues = []

      # Check Redis
      begin
        redis_url = GlitchCube.config.redis_url || 'redis://localhost:6379'
        redis = Redis.new(url: redis_url)
        redis.ping
        redis.quit # Clean up connection
      rescue StandardError
        healthy = false
        issues << 'Redis:down'
      end

      # Check database
      begin
        ActiveRecord::Base.connection.active?
      rescue StandardError
        healthy = false
        issues << 'DB:down'
      end

      # Check circuit breakers
      circuit_status = {}

      # Check Home Assistant breaker
      ha_breaker = Services::CircuitBreakerService.home_assistant_breaker
      if ha_breaker
        state = ha_breaker.state.to_s
        circuit_status['home_assistant'] = state
        issues << "home_assistant: #{state}" if state != 'closed'
      end

      # Check OpenRouter breaker
      or_breaker = Services::CircuitBreakerService.openrouter_breaker
      if or_breaker
        state = or_breaker.state.to_s
        circuit_status['openrouter'] = state
        issues << "openrouter: #{state}" if state != 'closed'
      end

      {
        healthy: healthy,
        issues: issues,
        circuit_breakers: circuit_status
      }
    end

    def generate_fallback_health_message(sinatra_health)
      # Generate a health message similar to HA's format when HA is down
      # Format: "HA:DOWN | API:status | Issues:xxx"

      api_status = sinatra_health[:healthy] ? 'OK' : 'DEGRADED'

      # Calculate uptime
      start_time = GlitchCube.start_time || Time.now
      uptime_hours = ((Time.now - start_time) / 3600).round(1)

      message_parts = [
        'HA:DOWN',
        "API:#{api_status}",
        "Up:#{uptime_hours}h"
      ]

      message_parts << "Issues:#{sinatra_health[:issues].join(',')}" if sinatra_health[:issues].any?

      # Add circuit breaker status if any are open
      open_breakers = sinatra_health[:circuit_breakers].reject { |_, state| state == 'closed' }
      if open_breakers.any?
        breaker_status = open_breakers.map { |name, state| "#{name}:#{state}" }.join(',')
        message_parts << "CB:#{breaker_status}"
      end

      message_parts.join(' | ')
    end
  end
end
