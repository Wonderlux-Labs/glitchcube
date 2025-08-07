# frozen_string_literal: true

require 'sidekiq'

module GlitchCube
  module Jobs
    class EntityDocumentationJob
      include Sidekiq::Job

      # Queue configuration
      sidekiq_options queue: :default, retry: 3, backtrace: true

      def perform(job_data)
        start_time = Time.now
        job_data = job_data.with_indifferent_access if job_data.respond_to?(:with_indifferent_access)

        log.info('📋 Starting entity documentation update',
                 trigger: job_data[:trigger],
                 timestamp: job_data[:timestamp])

        begin
          # Get fresh entities from Home Assistant
          home_assistant = HomeAssistantClient.new
          entities = home_assistant.states

          if entities.nil? || entities.empty?
            log.warn('⚠️ No entities returned from Home Assistant')
            return
          end

          # Update documentation file
          update_documentation(entities, job_data)

          # Update any cached entity lists in memory/Redis if needed
          update_cached_entities(entities)

          duration = ((Time.now - start_time) * 1000).round
          log.info('✅ Entity documentation updated successfully',
                   entity_count: entities.length,
                   duration_ms: duration,
                   trigger: job_data[:trigger])

        rescue StandardError => e
          log.error('❌ Entity documentation job failed',
                    error: e.message,
                    backtrace: e.backtrace.first(5),
                    job_data: job_data)
          raise e # Re-raise to trigger Sidekiq retry
        end
      end

      private

      def update_documentation(entities, job_data)
        # Organize entities by domain
        entities_by_domain = entities.group_by { |entity| 
          entity['entity_id'].split('.').first 
        }

        # Generate documentation content
        doc_content = generate_documentation_content(entities_by_domain, job_data)

        # Write to documentation file
        doc_path = File.join(GlitchCube.root, 'docs', 'home_assistant_entities.md')
        File.write(doc_path, doc_content)

        log.info('📄 Documentation file updated',
                 path: doc_path,
                 domains: entities_by_domain.keys.length,
                 total_entities: entities.length)
      end

      def generate_documentation_content(entities_by_domain, job_data)
        content = []
        content << "# Home Assistant Entities"
        content << ""
        content << "Last updated: #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}"
        content << "Update triggered by: #{job_data[:trigger] || 'unknown'}"
        
        if job_data[:changed_entity]
          content << "Changed entity: #{job_data[:changed_entity]}"
        end
        
        content << ""
        content << "## Summary"
        content << ""
        content << "| Domain | Count |"
        content << "|--------|-------|"
        
        entities_by_domain.sort.each do |domain, domain_entities|
          content << "| #{domain} | #{domain_entities.length} |"
        end
        
        content << ""
        content << "Total entities: #{entities_by_domain.values.flatten.length}"
        content << "Total domains: #{entities_by_domain.keys.length}"
        content << ""

        # Add detailed sections for important domains
        important_domains = %w[light binary_sensor media_player camera sensor switch]
        
        important_domains.each do |domain|
          next unless entities_by_domain[domain]
          
          content << "## #{domain.capitalize} Entities"
          content << ""
          
          entities_by_domain[domain].sort_by { |e| e['entity_id'] }.each do |entity|
            content << "### #{entity['entity_id']}"
            content << "- **State**: #{entity['state']}"
            content << "- **Last Changed**: #{entity['last_changed']}"
            
            if entity['attributes'] && !entity['attributes'].empty?
              interesting_attrs = entity['attributes'].select { |k, v| 
                !%w[last_changed last_updated].include?(k) && !v.nil?
              }.first(3)
              
              interesting_attrs.each do |key, value|
                content << "- **#{key.capitalize}**: #{value}"
              end
            end
            
            content << ""
          end
        end

        # Add quick reference section
        content << "## Quick Reference for Development"
        content << ""
        content << "### Available RGB Lights"
        if entities_by_domain['light']&.any?
          entities_by_domain['light'].each do |light|
            content << "- `#{light['entity_id']}` (#{light['state']})"
          end
        else
          content << "❌ No RGB light entities found - lighting features will need configuration"
        end
        
        content << ""
        content << "### Motion Sensors"
        motion_entities = (entities_by_domain['binary_sensor'] || []).select { |e| 
          e['entity_id'].include?('motion') 
        }
        
        if motion_entities.any?
          motion_entities.each do |sensor|
            content << "- `#{sensor['entity_id']}` (#{sensor['state']})"
          end
        else
          # Check for input_boolean motion detectors
          motion_inputs = (entities_by_domain['input_boolean'] || []).select { |e|
            e['entity_id'].include?('motion')
          }
          
          if motion_inputs.any?
            content << "Using input_boolean for motion detection:"
            motion_inputs.each do |input|
              content << "- `#{input['entity_id']}` (#{input['state']})"
            end
          else
            content << "❌ No motion sensors found"
          end
        end
        
        content << ""
        content << "### Media Players for TTS"
        if entities_by_domain['media_player']&.any?
          entities_by_domain['media_player'].each do |player|
            content << "- `#{player['entity_id']}` (#{player['state']})"
          end
        else
          content << "❌ No media player entities found"
        end

        content.join("\n")
      end

      def update_cached_entities(entities)
        # Update Redis cache if persistence is enabled
        return unless GlitchCube.persistence_enabled?

        begin
          redis = GlitchCube.redis_connection
          entities_by_domain = entities.group_by { |entity| 
            entity['entity_id'].split('.').first 
          }

          # Cache organized entities with expiration
          redis.setex('ha_entities_by_domain', 300, entities_by_domain.to_json) # 5 min expiry
          redis.setex('ha_entities_summary', 300, {
            total_entities: entities.length,
            total_domains: entities_by_domain.keys.length,
            domains: entities_by_domain.transform_values(&:length),
            last_updated: Time.now.iso8601
          }.to_json)

          log.debug('💾 Cached entity data in Redis',
                    cache_expiry: '5 minutes',
                    entity_count: entities.length)

        rescue StandardError => e
          log.warn('⚠️ Failed to cache entities in Redis',
                   error: e.message)
          # Don't fail the job for caching issues
        end
      end

      def log
        GlitchCube.logger
      end
    end
  end
end