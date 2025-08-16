# frozen_string_literal: true

module Routes
  module Api
    module Conversation
      extend ::Modules::ErrorHandling

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
            Services::Logging::SimpleLogger.track_error('api', e.message) if defined?(Services::Logging::SimpleLogger)
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
            # Preserve session_id from context or root level (support both string and symbol keys)
            # This allows HA to track multi-turn conversations and supports test requests
            context[:session_id] = request_body['session_id'] || request_body[:session_id] ||
                                   context['session_id'] || context[:session_id] ||
                                   SecureRandom.uuid
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
            request_id = SecureRandom.hex(8)
            $logger.info('📥 Conversation request',
                         tagged: %i[conversation api request],
                         request_id: request_id,
                         session_id: context[:session_id],
                         endpoint: '/api/v1/conversation',
                         message_preview: request_body['message']&.[](0..50),
                         voice_interaction: context[:voice_interaction])
            # Handle voice-specific context
            if context[:voice_interaction]
              context[:device_id] = context[:device_id]
              context[:conversation_id] = context[:conversation_id]
              context[:language] = context[:language] || 'en'
            end
            # Add model parameter to context if provided in request
            context[:model] = request_body['model'] if request_body['model']
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

            # Log what we're actually sending back to Home Assistant for TTS
            $logger.info('📢 TTS Callback Response',
                         tagged: %i[conversation tts_callback],
                         request_id: request_id,
                         session_id: context[:session_id],
                         response_data: response_data.inspect)
            # Log performance
            duration = ((Time.now - start_time) * 1000).round
            $logger.info('⏱️ Conversation performance',
                         tagged: %i[conversation performance],
                         request_id: request_id,
                         operation: 'conversation_processing',
                         duration_ms: duration,
                         success: true)

            # Wrap JSON response building to catch serialization errors
            begin
              json({
                     success: true,
                     data: response_data,
                     timestamp: Time.now.iso8601
                   })
            rescue StandardError => e
              $logger.error('❌ JSON response serialization failed',
                            tagged: %i[conversation api json_error],
                            request_id: request_id,
                            error: e.message,
                            response_data_keys: response_data.keys,
                            backtrace: e.backtrace.first(3))
              status 500
              json({ success: false, error: "Response serialization failed: #{e.message}" })
            end
          rescue StandardError => e
            $logger.error('❌ Conversation processing failed',
                          tagged: %i[conversation api error],
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
