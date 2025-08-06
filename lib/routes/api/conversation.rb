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
                context: context
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
                context: context
              )

              # Combine RAG and conversation results
              json({
                     success: true,
                     data: {
                       response: conv_result[:response],
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

          # Webhook endpoint for Home Assistant to trigger conversations
          app.post '/api/v1/ha_webhook' do
            content_type :json
            
            begin
              request_body = JSON.parse(request.body.read)
              conversation_handler = Services::ConversationHandlerService.new
              
              # Process HA webhook events
              case request_body['event_type']
              when 'conversation_started'
                # HA started a conversation, sync it
                context = {
                  ha_conversation_id: request_body['conversation_id'],
                  device_id: request_body['device_id'],
                  session_id: request_body['session_id'] || SecureRandom.uuid,
                  voice_interaction: true
                }
                
                # Find or create conversation and sync with HA
                conversation = Conversation.find_or_create_by(
                  ha_conversation_id: request_body['conversation_id']
                ) do |conv|
                  conv.session_id = context[:session_id]
                  conv.source = 'home_assistant'
                  conv.started_at = Time.current
                  conv.metadata = context
                end
                
                conversation_handler.sync_with_ha(
                  conversation,
                  request_body['conversation_id'],
                  request_body['device_id']
                )
                
                json({
                  success: true,
                  conversation_id: conversation.id,
                  ha_conversation_id: conversation.ha_conversation_id
                })
                
              when 'conversation_continued'
                # HA is continuing a conversation
                ha_conv_id = request_body['conversation_id']
                conversation = Conversation.find_by(ha_conversation_id: ha_conv_id)
                
                if conversation
                  # Process the message through your system
                  result = conversation_handler.process_conversation(
                    message: request_body['text'],
                    context: { 
                      ha_conversation_id: ha_conv_id,
                      device_id: request_body['device_id'],
                      voice_interaction: true,
                      session_id: conversation.session_id
                    }
                  )
                  
                  # Send response back to HA if needed
                  if result[:response] && request_body['send_response'] != false
                    conversation_handler.continue_ha_conversation(
                      ha_conv_id, 
                      result[:response],
                      { device_id: request_body['device_id'] }
                    )
                  end
                  
                  json({
                    success: true,
                    data: result
                  })
                else
                  # No existing conversation, create new one
                  result = conversation_handler.process_conversation(
                    message: request_body['text'],
                    context: {
                      ha_conversation_id: ha_conv_id,
                      device_id: request_body['device_id'],
                      voice_interaction: true,
                      session_id: SecureRandom.uuid
                    }
                  )
                  
                  json({
                    success: true,
                    data: result,
                    new_conversation: true
                  })
                end
                
              when 'trigger_action'
                # HA wants to trigger a specific action
                action = request_body['action']
                context = request_body['context'] || {}
                
                # Process action through conversation system
                result = conversation_handler.process_conversation(
                  message: "Execute action: #{action}",
                  context: context.merge(action_request: action),
                  mood: 'neutral'
                )
                
                json({
                  success: true,
                  action: action,
                  result: result
                })
                
              else
                json({
                  success: false,
                  error: "Unknown event type: #{request_body['event_type']}"
                })
              end
              
            rescue StandardError => e
              status 400
              json({ 
                success: false, 
                error: e.message,
                backtrace: e.backtrace.first(5)
              })
            end
          end
        end
      end
    end
  end
end