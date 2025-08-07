# frozen_string_literal: true

module GlitchCube
  module Routes
    module Api
      module Entities
        def self.registered(app)
          # Handle individual entity change notifications from Home Assistant
          app.post '/api/v1/entities/change_notification' do
            content_type :json

            begin
              request_body = JSON.parse(request.body.read)
              
              # Log the entity change
              log.info('🏠 Entity state changed',
                       entity_id: request_body['entity_id'],
                       old_state: request_body['old_state'],
                       new_state: request_body['new_state'],
                       domain: request_body['domain'],
                       source: request_body['source'])

              # Optionally trigger entity list refresh if significant change
              if self.class.should_trigger_refresh?(request_body)
                # Queue background job to refresh entity documentation
                require_relative '../../jobs/entity_documentation_job'
                Jobs::EntityDocumentationJob.perform_async({
                  trigger: 'entity_change',
                  changed_entity: request_body['entity_id'],
                  timestamp: Time.now.iso8601
                })
              end

              json({
                success: true,
                message: 'Entity change recorded',
                timestamp: Time.now.iso8601
              })

            rescue StandardError => e
              log.error('❌ Entity change notification failed',
                        error: e.message,
                        backtrace: e.backtrace.first(3))
              
              status 400
              json({
                success: false,
                error: e.message,
                timestamp: Time.now.iso8601
              })
            end
          end

          # Handle batch entity refresh requests
          app.post '/api/v1/entities/refresh' do
            content_type :json

            begin
              request_body = begin
                JSON.parse(request.body.read)
              rescue StandardError
                {}
              end

              log.info('🔄 Entity refresh requested',
                       batch_update: request_body['batch_update'],
                       source: request_body['source'])

              # Queue background job to refresh entity documentation
              require_relative '../../jobs/entity_documentation_job'
              job_id = Jobs::EntityDocumentationJob.perform_async({
                trigger: 'manual_refresh',
                batch_update: request_body['batch_update'],
                timestamp: Time.now.iso8601
              })

              json({
                success: true,
                message: 'Entity refresh queued',
                job_id: job_id,
                timestamp: Time.now.iso8601
              })

            rescue StandardError => e
              log.error('❌ Entity refresh failed',
                        error: e.message,
                        backtrace: e.backtrace.first(3))
              
              status 400
              json({
                success: false,
                error: e.message,
                timestamp: Time.now.iso8601
              })
            end
          end

          # Get current entity list organized by domain (direct API call method)
          app.get '/api/v1/entities/list' do
            content_type :json

            begin
              # Get fresh entities from Home Assistant
              home_assistant = HomeAssistantClient.new
              entities = home_assistant.states

              # Organize by domain
              entities_by_domain = entities.group_by { |entity| entity['entity_id'].split('.').first }
              
              # Add metadata
              entity_summary = {
                total_entities: entities.length,
                total_domains: entities_by_domain.keys.length,
                domains: entities_by_domain.transform_values(&:length),
                last_updated: Time.now.iso8601
              }

              json({
                success: true,
                summary: entity_summary,
                entities_by_domain: entities_by_domain,
                timestamp: Time.now.iso8601
              })

            rescue StandardError => e
              log.error('❌ Entity list retrieval failed',
                        error: e.message,
                        backtrace: e.backtrace.first(3))
              
              status 500
              json({
                success: false,
                error: e.message,
                timestamp: Time.now.iso8601
              })
            end
          end

          # Get entities by specific domain
          app.get '/api/v1/entities/:domain' do
            content_type :json
            domain = params[:domain]

            begin
              # Get entities from Home Assistant
              home_assistant = HomeAssistantClient.new
              all_entities = home_assistant.states

              # Filter by domain
              domain_entities = all_entities.select { |entity| 
                entity['entity_id'].start_with?("#{domain}.")
              }

              json({
                success: true,
                domain: domain,
                entity_count: domain_entities.length,
                entities: domain_entities,
                timestamp: Time.now.iso8601
              })

            rescue StandardError => e
              log.error('❌ Domain entity retrieval failed',
                        domain: domain,
                        error: e.message)
              
              status 500
              json({
                success: false,
                error: e.message,
                domain: domain,
                timestamp: Time.now.iso8601
              })
            end
          end

          private

          # Determine if entity change should trigger documentation refresh
          def self.should_trigger_refresh?(change_data)
            entity_id = change_data['entity_id']
            domain = change_data['domain']

            # Always refresh for new light entities (important for our lighting system)
            return true if domain == 'light'

            # Refresh for new binary sensors (motion, etc.)
            return true if domain == 'binary_sensor'

            # Refresh for new media players
            return true if domain == 'media_player'

            # Don't refresh for frequently changing sensors
            return false if %w[sensor input_number input_text].include?(domain)

            # Default: refresh for other domains
            true
          end
        end
      end
    end
  end
end