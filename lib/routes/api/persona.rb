# frozen_string_literal: true

require 'json'

module GlitchCube
  module Routes
    module Api
      module Persona
        def self.registered(app)
          # GET /api/v1/persona - Get current persona
          app.get '/api/v1/persona' do
            content_type :json

            begin
              current_persona = Services::PersonaStateService.get_current_persona
              usage_stats = Services::PersonaStateService.get_usage_stats

              json({
                     success: true,
                     current_persona: current_persona,
                     usage_stats: usage_stats,
                     timestamp: Time.now.iso8601
                   })
            rescue StandardError => e
              Services::Logging::SimpleLogger.log_error(error: e, message: 'Failed to get current persona')

              status 500
              json({
                     success: false,
                     error: e.message,
                     timestamp: Time.now.iso8601
                   })
            end
          end

          # POST /api/v1/persona - Set current persona
          app.post '/api/v1/persona' do
            content_type :json

            begin
              request_body = JSON.parse(request.body.read)
              persona_name = request_body['persona']

              unless persona_name
                status 400
                return json({
                              success: false,
                              error: 'Missing persona parameter',
                              timestamp: Time.now.iso8601
                            })
              end

              # Set the persona
              new_persona = Services::PersonaStateService.set_current_persona(persona_name)

              # Log the persona change
              Services::Logging::SimpleLogger.info('Persona changed via API',
                                                   tagged: %i[api persona],
                                                   new_persona: new_persona,
                                                   request_ip: request.ip)

              json({
                     success: true,
                     persona: new_persona,
                     message: "Persona changed to #{new_persona}",
                     timestamp: Time.now.iso8601
                   })
            rescue ArgumentError => e
              status 400
              json({
                     success: false,
                     error: e.message,
                     timestamp: Time.now.iso8601
                   })
            rescue StandardError => e
              Services::Logging::SimpleLogger.log_error(error: e, message: 'Failed to set persona')

              status 500
              json({
                     success: false,
                     error: e.message,
                     timestamp: Time.now.iso8601
                   })
            end
          end

          # GET /api/v1/personas - List available personas
          app.get '/api/v1/personas' do
            content_type :json

            begin
              available = ::Personas::PersonaFactory.available_personas
              current = Services::PersonaStateService.get_current_persona

              # Build persona details
              personas = available.map do |name|
                {
                  name: name,
                  active: name == current,
                  display_name: name.capitalize
                }
              end

              json({
                     success: true,
                     personas: personas,
                     current: current,
                     total: personas.size,
                     timestamp: Time.now.iso8601
                   })
            rescue StandardError => e
              Services::Logging::SimpleLogger.log_error(error: e, message: 'Failed to list personas')

              status 500
              json({
                     success: false,
                     error: e.message,
                     timestamp: Time.now.iso8601
                   })
            end
          end

          # POST /api/v1/persona/sync - Sync with Home Assistant
          app.post '/api/v1/persona/sync' do
            content_type :json

            begin
              request_body = begin
                JSON.parse(request.body.read)
              rescue StandardError
                {}
              end

              direction = request_body['direction'] || 'from_ha'

              case direction
              when 'from_ha'
                # Sync from Home Assistant to Ruby app
                Services::PersonaStateService.sync_from_home_assistant
                current = Services::PersonaStateService.get_current_persona

                json({
                       success: true,
                       message: 'Synced from Home Assistant',
                       current_persona: current,
                       timestamp: Time.now.iso8601
                     })
              when 'to_ha'
                # Sync from Ruby app to Home Assistant
                current = Services::PersonaStateService.get_current_persona
                success = Services::PersonaStateService.sync_with_home_assistant(current)

                json({
                       success: success,
                       message: success ? 'Synced to Home Assistant' : 'Failed to sync to Home Assistant',
                       current_persona: current,
                       timestamp: Time.now.iso8601
                     })
              else
                status 400
                json({
                       success: false,
                       error: "Invalid sync direction: #{direction}. Use 'from_ha' or 'to_ha'",
                       timestamp: Time.now.iso8601
                     })
              end
            rescue StandardError => e
              Services::Logging::SimpleLogger.log_error(error: e, message: 'Failed to sync persona')

              status 500
              json({
                     success: false,
                     error: e.message,
                     timestamp: Time.now.iso8601
                   })
            end
          end

          # DELETE /api/v1/persona/state - Clear all persona state
          app.delete '/api/v1/persona/state' do
            content_type :json

            begin
              success = Services::PersonaStateService.clear_state!

              json({
                     success: success,
                     message: success ? 'Persona state cleared' : 'Failed to clear persona state',
                     timestamp: Time.now.iso8601
                   })
            rescue StandardError => e
              Services::Logging::SimpleLogger.log_error(error: e, message: 'Failed to clear persona state')

              status 500
              json({
                     success: false,
                     error: e.message,
                     timestamp: Time.now.iso8601
                   })
            end
          end
        end
      end
    end
  end
end
