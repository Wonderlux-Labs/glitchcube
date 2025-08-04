# frozen_string_literal: true

module Services
  module Kiosk
    # Extracts environmental data from Home Assistant
    class EnvironmentalData
      def initialize(home_assistant_client)
        @home_assistant = home_assistant_client
      end

      def fetch
        states = Services::CircuitBreakerService.home_assistant_breaker.call do
          @home_assistant.states
        end

        {
          battery_level: extract_sensor_value(states, 'sensor.battery_level', '%'),
          temperature: extract_sensor_value(states, 'sensor.temperature', '°C'),
          motion_detected: extract_binary_sensor(states, 'binary_sensor.motion'),
          lighting_status: extract_light_status(states, 'light.glitch_cube'),
          last_updated: Time.now.iso8601
        }
      rescue CircuitBreaker::CircuitOpenError
        { status: 'circuit_open', message: 'Home Assistant temporarily unavailable' }
      rescue StandardError => e
        { status: 'error', message: e.message }
      end

      private

      def extract_sensor_value(states, entity_id, unit = nil)
        entity = states.find { |s| s['entity_id'] == entity_id }
        return nil unless entity

        value = entity['state']
        unit ? "#{value}#{unit}" : value
      end

      def extract_binary_sensor(states, entity_id)
        entity = states.find { |s| s['entity_id'] == entity_id }
        return nil unless entity

        entity['state'] == 'on'
      end

      def extract_light_status(states, entity_id)
        entity = states.find { |s| s['entity_id'] == entity_id }
        return nil unless entity

        {
          state: entity['state'],
          brightness: entity.dig('attributes', 'brightness'),
          color: entity.dig('attributes', 'rgb_color')
        }
      end
    end
  end
end