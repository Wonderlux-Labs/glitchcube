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
              start_time = Time.now

              # Add session ID to context if not present
              context = request_body['context'] || {}
              context[:session_id] ||= request.session[:session_id] || SecureRandom.uuid
              
              # Log conversation request with context
              log.with_context(
                request_id: SecureRandom.hex(8),
                session_id: context[:session_id],
                endpoint: '/api/v1/conversation'
              ) do
                log.info("📥 Conversation request", 
                  message_preview: request_body['message']&.[](0..50),
                  voice_interaction: context[:voice_interaction]
                )

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
            rescue StandardError => e
              log.error("❌ Conversation processing failed", 
                error: e.message,
                backtrace: e.backtrace.first(3)
              )
              
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

              # Get conversation response using module directly  
              conversation_module = ConversationModule.new
              conv_result = conversation_module.call(
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

              # Generate appropriate conversation starter - use default if no custom message
              conversation_text = custom_message || "Hello! I noticed some activity and wanted to check in."

              # Send to Home Assistant conversation service using client directly
              ha_client = HomeAssistantClient.new
              ha_response = ha_client.process_voice_command(conversation_text)

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
              
              # Process HA webhook events
              case request_body['event_type']
              when 'conversation_started'
                # HA started a conversation - just acknowledge it
                context = {
                  ha_conversation_id: request_body['conversation_id'],
                  device_id: request_body['device_id'],
                  session_id: request_body['session_id'] || SecureRandom.uuid,
                  voice_interaction: true
                }
                
                json({
                  success: true,
                  session_id: context[:session_id],
                  ha_conversation_id: context[:ha_conversation_id]
                })
                
              when 'conversation_continued'
                # HA is continuing a conversation - process through module directly
                context = { 
                  ha_conversation_id: request_body['conversation_id'],
                  device_id: request_body['device_id'],
                  voice_interaction: true,
                  session_id: request_body['session_id'] || SecureRandom.uuid
                }
                
                # Process the message through conversation module
                conversation_module = ConversationModule.new
                result = conversation_module.call(
                  message: request_body['text'],
                  context: context
                )
                
                # Send response back to HA if needed
                if result[:response] && request_body['send_response'] != false
                  begin
                    home_assistant = HomeAssistantClient.new
                    home_assistant.call_service(
                      'conversation',
                      'process', 
                      {
                        text: result[:response],
                        conversation_id: request_body['conversation_id'],
                        device_id: request_body['device_id'] || 'glitchcube',
                        language: 'en'
                      }
                    )
                  rescue StandardError => e
                    # Log error but don't fail the request
                    puts "Failed to continue HA conversation: #{e.message}"
                  end
                end
                
                json({
                  success: true,
                  data: result
                })
                
              when 'trigger_action'
                # HA wants to trigger a specific action
                action = request_body['action']
                context = (request_body['context'] || {}).merge(action_request: action)
                
                # Process action through conversation module
                conversation_module = ConversationModule.new
                result = conversation_module.call(
                  message: "Execute action: #{action}",
                  context: context
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