# frozen_string_literal: true

require 'redis'
require 'json'

module Services
  class PersonaStateService
    REDIS_KEY = 'glitchcube:current_persona'
    STATS_KEY_PREFIX = 'glitchcube:persona_stats:'
    DEFAULT_PERSONA = 'buddy'
    TTL = 86_400 # 24 hours

    class << self
      # Get the current persona from Redis or default to 'buddy'
      def get_current_persona
        return DEFAULT_PERSONA unless redis_available?

        persona = redis_client.get(REDIS_KEY)
        persona || DEFAULT_PERSONA
      rescue StandardError => e
        ::Services::Logging::SimpleLogger.log_error(error: e, message: 'Failed to get current persona from Redis')
        DEFAULT_PERSONA
      end

      # Set the current persona in Redis and optionally sync with Home Assistant
      def set_current_persona(persona_name, sync_with_ha: true)
        normalized_name = normalize_persona_name(persona_name)

        # Validate persona exists
        unless Personas::BasePersona.persona_exists?(normalized_name) || normalized_name == DEFAULT_PERSONA
          raise ArgumentError, "Unknown persona: #{persona_name}"
        end

        # Store in Redis if available
        if redis_available?
          redis_client.set(REDIS_KEY, normalized_name, ex: TTL)
          increment_usage_stats(normalized_name)
        end

        # Sync with Home Assistant if requested
        sync_with_home_assistant(normalized_name) if sync_with_ha

        ::Services::Logging::SimpleLogger.info('Persona changed',
                                               tagged: [:persona],
                                               new_persona: normalized_name)

        normalized_name
      rescue ArgumentError
        # Let ArgumentError bubble up for API error handling
        raise
      rescue StandardError => e
        ::Services::Logging::SimpleLogger.log_error(error: e, message: 'Failed to set current persona')
        raise
      end

      # Sync current persona state with Home Assistant
      def sync_with_home_assistant(persona_name = nil)
        persona_name ||= get_current_persona

        begin
          ha_client = Core::HomeAssistantClient.new

          # Update the input_text.current_persona entity with exact persona name
          # Using lowercase name so HA automations can match exactly
          ha_client.set_state(
            'input_text.current_persona',
            persona_name.downcase,
            attributes: {
              friendly_name: 'Current AI Persona',
              icon: 'mdi:robot',
              display_name: persona_name.capitalize,
              last_changed_by: 'glitchcube_api',
              timestamp: Time.now.iso8601
            }
          )

          ::Services::Logging::SimpleLogger.debug('Synced persona with Home Assistant',
                                                  tagged: %i[persona home_assistant],
                                                  persona: persona_name)
          true
        rescue StandardError => e
          ::Services::Logging::SimpleLogger.log_error(error: e, message: 'Failed to sync persona with Home Assistant')
          false
        end
      end

      # Get persona from Home Assistant
      def get_persona_from_home_assistant
        ha_client = Core::HomeAssistantClient.new
        state = ha_client.state('input_text.current_persona')

        return DEFAULT_PERSONA unless state.is_a?(Hash) && state['state']

        # Return default if state is unavailable or unknown
        normalized = normalize_persona_name(state['state'])
        return DEFAULT_PERSONA if %w[unavailable unknown].include?(normalized)

        normalized
      rescue StandardError => e
        ::Services::Logging::SimpleLogger.log_error(error: e, message: 'Failed to get persona from Home Assistant')
        DEFAULT_PERSONA
      end

      # Sync from Home Assistant to Redis (for when HA changes the persona)
      def sync_from_home_assistant
        ha_persona = get_persona_from_home_assistant
        set_current_persona(ha_persona, sync_with_ha: false)
      end

      # Get usage statistics for personas
      def get_usage_stats
        return {} unless redis_available?

        stats = {}
        personas = Personas::PersonaFactory.available_personas
        personas << DEFAULT_PERSONA

        personas.each do |persona|
          key = "#{STATS_KEY_PREFIX}#{persona}"
          count = redis_client.get(key).to_i
          stats[persona] = count if count.positive?
        end

        stats
      rescue StandardError => e
        ::Services::Logging::SimpleLogger.log_error(error: e, message: 'Failed to get persona usage stats')
        {}
      end

      # Clear all persona state
      def clear_state!
        if redis_available?
          redis_client.del(REDIS_KEY)

          # Clear all stats keys
          keys = redis_client.keys("#{STATS_KEY_PREFIX}*")
          redis_client.del(*keys) if keys.any?
        end

        ::Services::Logging::SimpleLogger.info('Cleared all persona state')
        true
      rescue StandardError => e
        ::Services::Logging::SimpleLogger.log_error(error: e, message: 'Failed to clear persona state')
        false
      end

      private

      def normalize_persona_name(persona_name)
        return DEFAULT_PERSONA if persona_name.nil? || persona_name.to_s.strip.empty?

        persona_name.to_s.downcase.strip
      end

      def increment_usage_stats(persona_name)
        return unless redis_available?

        key = "#{STATS_KEY_PREFIX}#{persona_name}"
        redis_client.incr(key)
        redis_client.expire(key, 30 * 86_400) # Keep stats for 30 days
      rescue StandardError => e
        ::Services::Logging::SimpleLogger.log_error(error: e, message: 'Failed to increment persona usage stats')
      end

      def redis_available?
        return false unless GlitchCube.config.redis_url

        @redis_available ||= begin
          redis_client.ping == 'PONG'
        rescue StandardError
          false
        end
      end

      def redis_client
        @redis_client ||= Redis.new(url: GlitchCube.config.redis_url)
      end
    end
  end
end
