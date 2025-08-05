# frozen_string_literal: true

module GlitchCube
  module Routes
    module Api
      module Conversation
        def self.registered(app)
          # Basic conversation test endpoint
          app.post '/api/v1/test' do
            content_type :json

            begin
              request_body = JSON.parse(request.body.read)
              message = request_body['message'] || 'Hello, Glitch Cube!'

              # Use the conversation handler service
              conversation_handler = Services::ConversationHandlerService.new
              result = conversation_handler.conversation_module.call(
                message: message,
                context: request_body['context'] || {}
              )

              json({
                     success: true,
                     response: result[:response],
                     timestamp: Time.now.iso8601
                   })
            rescue StandardError => e
              status 500
              json({
                     success: false,
                     error: e.message,
                     timestamp: Time.now.iso8601
                   })
            end
          end

          # Main conversation endpoint with full HA integration
          app.post '/api/v1/conversation' do
            content_type :json

            begin
              request_body = JSON.parse(request.body.read)

              # Add session ID to context if not present
              context = request_body['context'] || {}
              context[:session_id] ||= request.session[:session_id] || SecureRandom.uuid

              # Handle voice-specific context
              if context[:voice_interaction]
                context[:device_id] = context[:device_id]
                context[:conversation_id] = context[:conversation_id]
                context[:language] = context[:language] || 'en'
              end

              # Use the conversation handler service
              conversation_handler = Services::ConversationHandlerService.new
              response_data = conversation_handler.process_conversation(
                message: request_body['message'],
                context: context,
                mood: request_body['mood'] || 'neutral'
              )

              json({
                     success: true,
                     data: response_data,
                     timestamp: Time.now.iso8601
                   })
            rescue StandardError => e
              status 400
              json({
                     success: false,
                     error: e.message
                   })
            end
          end

          # RAG-enhanced conversation endpoint
          app.post '/api/v1/conversation/with_context' do
            content_type :json

            begin
              request_body = JSON.parse(request.body.read)
              message = request_body['message']

              # Use RAG to get relevant context
              require_relative '../../services/context_retrieval_service'
              rag = Services::SimpleRAG.new
              rag_result = rag.answer_with_context(message)

              # Enhance the response with context
              context = request_body['context'] || {}
              context[:rag_contexts] = rag_result[:contexts_used]
              context[:session_id] ||= request.session[:session_id] || SecureRandom.uuid

              # Get conversation response using handler service
              conversation_handler = Services::ConversationHandlerService.new
              conv_result = conversation_handler.conversation_module.call(
                message: message,
                context: context,
                mood: request_body['mood'] || 'neutral'
              )

              # Combine RAG and conversation results
              json({
                     success: true,
                     data: {
                       response: conv_result[:response],
                       suggested_mood: conv_result[:suggested_mood],
                       confidence: [conv_result[:confidence], rag_result[:confidence]].max,
                       contexts_used: rag_result[:contexts_used]
                     },
                     timestamp: Time.now.iso8601
                   })
            rescue StandardError => e
              status 400
              json({
                     success: false,
                     error: e.message
                   })
            end
          end

          # Proactive conversation endpoint (for starting conversations from automations)
          app.post '/api/v1/conversation/start' do
            content_type :json

            begin
              request_body = JSON.parse(request.body.read)

              # Generate proactive message based on trigger
              trigger_type = request_body['trigger'] || 'automation'
              context = request_body['context'] || {}
              custom_message = request_body['message']

              conversation_handler = Services::ConversationHandlerService.new

              # Generate appropriate conversation starter
              conversation_text = custom_message || conversation_handler.generate_proactive_message(trigger_type, context)

              # Send to Home Assistant conversation service
              ha_response = conversation_handler.send_conversation_to_ha(conversation_text, context)

              json({
                     success: true,
                     data: {
                       message: conversation_text,
                       ha_response: ha_response
                     },
                     timestamp: Time.now.iso8601
                   })
            rescue StandardError => e
              status 400
              json({
                     success: false,
                     error: e.message
                   })
            end
          end
        end
      end
    end
  end
end