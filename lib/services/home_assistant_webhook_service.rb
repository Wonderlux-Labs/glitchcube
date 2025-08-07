# frozen_string_literal: true

require 'httparty'

module Services
  class HomeAssistantWebhookService
    include HTTParty

    def initialize
      @webhook_url = "#{GlitchCube.config.home_assistant.url}/api/webhook/glitchcube_update"
    end

    # Send update to Home Assistant via webhook
    def send_update(data)
      response = self.class.post(
        @webhook_url,
        body: data.to_json,
        headers: { 'Content-Type' => 'application/json' },
        timeout: 5
      )

      {
        success: response.success?,
        status_code: response.code,
        response: response.parsed_response
      }
    rescue StandardError => e
      GlitchCube.logger.error("Failed to send webhook to HA: #{e.message}")
      {
        success: false,
        error: e.message
      }
    end

    # Convenience methods for common updates
    def update_persona(persona_name)
      send_update({ persona: persona_name })
    end

    def update_environment(environment)
      send_update({ environment: environment })
    end

    def update_weather(weather)
      send_update({ weather: weather })
    end

    def update_sound_level(db_level)
      send_update({ sound_db: db_level })
    end

    def record_interaction(source: 'api')
      send_update({
                    interaction: true,
                    source: source,
                    timestamp: Time.now.iso8601
                  })
    end

    # Send multiple updates at once
    def bulk_update(updates = {})
      send_update(updates)
    end
  end
end
