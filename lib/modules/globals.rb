# frozen_string_literal: true

require_relative '../services/logging/simple_logger'
module Modules
  module Globals
    # Global logger instance
    Logger = Services::Logging::SimpleLogger

    class << self
      # Persona state (read-only global access)
      def persona
        Services::PersonaStateService.get_current_persona
      end

      # Redis-backed global state
      def redis
        @redis ||= Redis.new(url: GlitchCube.config.redis_url)
      end

      # Global Home Assistant client
      def home_assistant
        @home_assistant ||= Services::Core::HomeAssistantClient.new
      end

      # World state (stored in Home Assistant)
      def world_state
        Services::Core::HomeAssistantClient.get_world_state
      end

      def set_world_state(attr:, val:)
        current_attributes = world_state
        current_attributes[attr.to_s] = val
        home_assistant.update_world_state_sensor(current_attributes)
      end

      def delete_world_state(attr:)
        current_attributes = world_state
        current_attributes.delete(attr.to_s)
        home_assistant.update_world_state_sensor(current_attributes)
      end

      def time_world_state(attr:, time: Time.current)
        set_world_state(attr: attr, val: time.iso8601)
      end

      # Current location (GPS)
      def location
        Services::Gps::GPSTrackingService.new.current_location
      end

      # Device/installation info
      def device_id
        GlitchCube.config.device.id
      end

      def installation_location
        GlitchCube.config.device.location
      end

      # Common Redis keys for global state
      def get_redis_state(key)
        redis.get(key)
      end

      def set_redis_state(key, value, expiry: nil)
        if expiry
          redis.setex(key, expiry, value)
        else
          redis.set(key, value)
        end
      end

      def delete_redis_state(key)
        redis.del(key)
      end

      # Tool failure state (used by async tools)
      def get_tool_failure(session_id)
        get_redis_state("tool_failure:#{session_id}")
      end

      def set_tool_failure(session_id, message, expiry: 300)
        set_redis_state("tool_failure:#{session_id}", message, expiry: expiry)
      end

      def clear_tool_failure(session_id)
        delete_redis_state("tool_failure:#{session_id}")
      end
    end
  end
end

# Convenience alias for shorter access
G = Modules::Globals
