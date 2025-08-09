# frozen_string_literal: true

require_relative '../../services/conversation_session'
require_relative '../../services/logger_service'
require_relative '../../modules/error_handling'

module GlitchCube
  module Routes
    module Api
      module Conversation
        extend ErrorHandling

        def self.registered(app)
          # Basic conversation test endpoint
          app.post '/api/v1/test' do
            content_type :json

            begin
              request_body = JSON.parse(request.body.read)
              message = request_body['message'] || 'Hello, Glitch Cube!'

              # Use the conversation module directly
              conversation_module = ConversationModule.new
              result = conversation_module.call(
                message: message,
                context: request_body['context'] || {}
              )

              json({
                     success: true,
                     response: result[:response],
                     timestamp: Time.now.iso8601
                   })
            rescue StandardError => e
              # Log the error
              puts "❌ Error in /api/v1/test: #{e.class.name} - #{e.message}"
              ::Services::LoggerService.track_error('api', e.message) if defined?(::Services::LoggerService)

              status 500
              json({
                     success: false,
                     error: e.message,
                     timestamp: Time.now.iso8601
                   })
            end
          end

          # PRIMARY CONVERSATION ENDPOINT - Phase 3 Sinatra-Centric Architecture
          # This is the unified endpoint for all conversation interactions:
          # - Home Assistant voice interactions via custom conversation agent
          # - Direct API calls from web interfaces, admin tools, etc.
          # - Multi-turn conversation sessions with automatic state management
          # - Tool execution via LLM function calling
          # - Unified TTS and hardware control through tools
          app.post '/api/v1/conversation' do
            content_type :json

            begin
              request_body = JSON.parse(request.body.read)
              start_time = Time.now

              # Phase 3.5: Ultra-simple session management
              # Use session_id from request context if provided (e.g., from HA)
              # Otherwise generate a new one
              context = request_body['context'] || {}

              # Preserve session_id from context if provided (support both string and symbol keys)
              # This allows HA to track multi-turn conversations
              context[:session_id] = context['session_id'] || context[:session_id] || SecureRandom.uuid

              # Memory/resource guard: reject oversize context payloads
              if context['conversation_history'].is_a?(Array) && context['conversation_history'].size > 100
                status 413
                return json({ success: false, error: 'conversation_history too large (max 100 entries)' })
              end
              if context['metadata'].is_a?(Hash)
                metadata_size = context['metadata'].to_json.bytesize
                if metadata_size > 100 * 1024
                  status 413
                  return json({ success: false, error: 'metadata too large (max 100KB)' })
                end
              end
              context_size = context.to_json.bytesize
              if context_size > 200 * 1024
                status 413
                return json({ success: false, error: 'context payload too large (max 200KB)' })
              end

              # Log conversation request with context
              log.with_context(
                request_id: SecureRandom.hex(8),
                session_id: context[:session_id],
                endpoint: '/api/v1/conversation'
              ) do
                log.info('📥 Conversation request',
                         message_preview: request_body['message']&.[](0..50),
                         voice_interaction: context[:voice_interaction])

                # Handle voice-specific context
                if context[:voice_interaction]
                  context[:device_id] = context[:device_id]
                  context[:conversation_id] = context[:conversation_id]
                  context[:language] = context[:language] || 'en'
                end

                # Use the conversation module directly
                conversation_module = ConversationModule.new
                response_data = conversation_module.call(
                  message: request_body['message'],
                  context: context
                )

                # Sanitize response to prevent XSS
                if response_data.is_a?(Hash) && response_data[:response].is_a?(String)
                  # Remove script tags and common XSS vectors
                  sanitized = response_data[:response].gsub(%r{<script.*?>.*?</script>}im, '')
                  sanitized = sanitized.gsub(/alert\s*\(/i, '')
                  response_data[:response] = sanitized
                end

                # Add backward compatibility mapping for end_conversation
                if response_data.is_a?(Hash) && response_data.key?(:continue_conversation)
                  # Map continue_conversation to end_conversation for backward compatibility
                  response_data[:end_conversation] = !response_data[:continue_conversation]
                end

                # Log performance
                duration = ((Time.now - start_time) * 1000).round
                log.performance(
                  operation: 'conversation_processing',
                  duration: duration,
                  success: true
                )

                json({
                       success: true,
                       data: response_data,
                       timestamp: Time.now.iso8601
                     })
              end
            rescue CircuitBreaker::CircuitOpenError => e
              log.error('⛔️ LLM circuit breaker is open',
                        error: e.message,
                        backtrace: e.backtrace&.first(3))

              status 503
              json({
                     success: false,
                     error: 'LLM temporarily unavailable (circuit breaker open)'
                   })
            rescue StandardError => e
              log.error('❌ Conversation processing failed',
                        error: e.message,
                        backtrace: e.backtrace.first(3))

              status 400
              json({
                     success: false,
                     error: e.message
                   })
            end
          end

          # NOTE: /api/v1/conversation/with_context endpoint has been removed
          # as part of Phase 3.5 consolidation. All RAG functionality
          # is now handled within the main /api/v1/conversation endpoint.
        end
      end
    end
  end
end
