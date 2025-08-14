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

              # Entity change logged - manual entity refresh available via API

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

              # NOTE: EntityDocumentationJob now run manually via script
              # Use: ruby scripts/update_ha_entities_doc.rb

              json({
                     success: true,
                     message: 'Entity refresh request logged - run manual script to update documentation',
                     manual_command: 'ruby scripts/update_ha_entities_doc.rb',
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
              domain_entities = all_entities.select do |entity|
                entity['entity_id'].start_with?("#{domain}.")
              end

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
        end
      end
    end
  end
end
