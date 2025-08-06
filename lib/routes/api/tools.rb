# frozen_string_literal: true

module GlitchCube
  module Routes
    module Api
      module Tools
        def self.registered(app)
          # Tool test endpoint using ReAct pattern
          app.post '/api/v1/tool_test' do
            content_type :json

            begin
              request_body = JSON.parse(request.body.read)
              message = request_body['message'] || 'Tell me about the battery status'

              # Use the conversation handler service to get tool agent
              conversation_handler = Services::ConversationHandlerService.new
              result = conversation_handler.tool_agent.call(question: message)

              json({
                     success: true,
                     response: result[:answer],
                     timestamp: Time.now.iso8601
                   })
            rescue StandardError => e
              status 500
              json({
                     success: false,
                     error: e.message,
                     backtrace: e.backtrace[0..5]
                   })
            end
          end

          # Home Assistant integration endpoint
          app.post '/api/v1/home_assistant' do
            content_type :json

            begin
              request_body = JSON.parse(request.body.read)
              message = request_body['message'] || 'Check all sensors and set the light to blue'

              # Use the conversation handler service to get HA agent
              conversation_handler = Services::ConversationHandlerService.new
              result = conversation_handler.home_assistant_agent.call(request: message)

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
                     backtrace: e.backtrace[0..5]
                   })
            end
          end
        end
      end
    end
  end
end
