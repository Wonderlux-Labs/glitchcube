# frozen_string_literal: true

module GlitchCube
  module Services
    class EntityManagerService
      class << self
        # Get entities organized by domain with optional caching
        def get_entities_by_domain(use_cache: true)
          if use_cache && GlitchCube.persistence_enabled?
            cached = get_cached_entities_by_domain
            return cached if cached
          end

          # Fetch fresh from Home Assistant
          fetch_fresh_entities_by_domain
        end

        # Get entities for specific domain
        def get_domain_entities(domain, use_cache: true)
          entities_by_domain = get_entities_by_domain(use_cache: use_cache)
          entities_by_domain[domain] || []
        end

        # Get available RGB light entities
        def get_rgb_lights(use_cache: true)
          light_entities = get_domain_entities('light', use_cache: use_cache)
          
          # Filter for RGB-capable lights based on attributes
          light_entities.select do |light|
            attrs = light['attributes'] || {}
            attrs['supported_color_modes']&.include?('rgb') ||
            attrs['supported_color_modes']&.include?('rgbw') ||
            attrs['color_mode'] == 'rgb' ||
            attrs['color_mode'] == 'rgbw'
          end
        end

        # Get motion detection entities
        def get_motion_sensors(use_cache: true)
          binary_sensors = get_domain_entities('binary_sensor', use_cache: use_cache)
          input_booleans = get_domain_entities('input_boolean', use_cache: use_cache)
          
          motion_sensors = []
          
          # Check binary sensors for motion
          motion_sensors += binary_sensors.select { |sensor|
            sensor['entity_id'].include?('motion') ||
            sensor['attributes']&.dig('device_class') == 'motion'
          }
          
          # Check input_booleans for motion (like our current setup)
          motion_sensors += input_booleans.select { |input|
            input['entity_id'].include?('motion')
          }
          
          motion_sensors
        end

        # Get media players suitable for TTS
        def get_media_players(use_cache: true)
          get_domain_entities('media_player', use_cache: use_cache)
        end

        # Get hardware capability summary
        def get_hardware_capabilities(use_cache: true)
          {
            rgb_lights: get_rgb_lights(use_cache: use_cache),
            motion_sensors: get_motion_sensors(use_cache: use_cache),
            media_players: get_media_players(use_cache: use_cache),
            summary: {
              rgb_light_count: get_rgb_lights(use_cache: use_cache).length,
              motion_sensor_count: get_motion_sensors(use_cache: use_cache).length,
              media_player_count: get_media_players(use_cache: use_cache).length,
              lighting_available: get_rgb_lights(use_cache: use_cache).any?,
              motion_detection_available: get_motion_sensors(use_cache: use_cache).any?,
              tts_available: get_media_players(use_cache: use_cache).any?
            }
          }
        end

        # Force refresh of entities and update cache
        def refresh_entities!
          entities_by_domain = fetch_fresh_entities_by_domain
          update_entity_cache(entities_by_domain) if GlitchCube.persistence_enabled?
          entities_by_domain
        end

        private

        def get_cached_entities_by_domain
          return nil unless GlitchCube.persistence_enabled?

          begin
            redis = GlitchCube.redis_connection
            cached_json = redis.get('ha_entities_by_domain')
            return nil unless cached_json

            JSON.parse(cached_json)
          rescue StandardError => e
            GlitchCube.logger.warn('⚠️ Failed to retrieve cached entities',
                                   error: e.message)
            nil
          end
        end

        def fetch_fresh_entities_by_domain
          home_assistant = HomeAssistantClient.new
          entities = home_assistant.states
          
          return {} if entities.nil? || entities.empty?

          entities_by_domain = entities.group_by { |entity| 
            entity['entity_id'].split('.').first 
          }

          # Update cache if available
          update_entity_cache(entities_by_domain) if GlitchCube.persistence_enabled?

          entities_by_domain
        end

        def update_entity_cache(entities_by_domain)
          return unless GlitchCube.persistence_enabled?

          begin
            redis = GlitchCube.redis_connection
            
            # Cache organized entities with 5-minute expiration
            redis.setex('ha_entities_by_domain', 300, entities_by_domain.to_json)
            
            # Cache summary data
            summary = {
              total_entities: entities_by_domain.values.flatten.length,
              total_domains: entities_by_domain.keys.length,
              domains: entities_by_domain.transform_values(&:length),
              last_updated: Time.now.iso8601
            }
            redis.setex('ha_entities_summary', 300, summary.to_json)

            GlitchCube.logger.debug('💾 Updated entity cache',
                                    entity_count: summary[:total_entities],
                                    domain_count: summary[:total_domains])

          rescue StandardError => e
            GlitchCube.logger.warn('⚠️ Failed to update entity cache',
                                   error: e.message)
          end
        end
      end
    end
  end
end