# frozen_string_literal: true

require 'httparty'

module Services
  class HealthPushService
    include HTTParty

    def initialize
      @uptime_kuma_url = ENV['UPTIME_KUMA_PUSH_URL']
      @home_assistant_client = Services::HomeAssistantClient.new
    end

    # Push health status to Uptime Kuma
    # Reads consolidated health data from Home Assistant sensor.health_monitoring
    def push_health_status
      health_data = fetch_health_monitoring_data
      
      if @uptime_kuma_url && !@uptime_kuma_url.empty?
        push_to_uptime_kuma(health_data)
      else
        # Just return the health data if no Uptime Kuma URL configured
        { 
          status: 'ok',
          message: health_data
        }
      end
    rescue => e
      # Even on error, we're technically "up" if this endpoint responds
      { 
        status: 'error',
        message: "Health check error: #{e.message}"
      }
    end

    private

    def fetch_health_monitoring_data
      health_data = @home_assistant_client.get_state('sensor.health_monitoring')
      
      if health_data && health_data['state']
        health_data['state']
      else
        'Unable to fetch health monitoring data'
      end
    end

    def push_to_uptime_kuma(health_message)
      response = self.class.get(
        @uptime_kuma_url,
        query: {
          status: 'up',
          msg: health_message,
          ping: 1
        },
        timeout: 5
      )
      
      { 
        status: 'pushed',
        message: health_message,
        uptime_kuma_response: response.code
      }
    end
  end
end