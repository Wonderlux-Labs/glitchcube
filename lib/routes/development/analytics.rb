# frozen_string_literal: true

module GlitchCube
  module Routes
    module Development
      module Analytics
        def self.registered(app)
          # Only register these routes in development and test environments
          return unless app.development? || app.test?

          # Error statistics endpoint
          app.get '/api/v1/logs/errors' do
            content_type :json

            json({
                   error_summary: ::Services::LoggerService.error_summary,
                   error_stats: ::Services::LoggerService.error_stats
                 })
          end

          # Circuit breaker status endpoint
          app.get '/api/v1/logs/circuit_breakers' do
            content_type :json

            json({
                   circuit_breakers: ::Services::CircuitBreakerService.status,
                   actions: {
                     reset_all: '/api/v1/logs/circuit_breakers/reset',
                     reset_single: '/api/v1/logs/circuit_breakers/:name/reset'
                   }
                 })
          end

          # Reset all circuit breakers
          app.post '/api/v1/logs/circuit_breakers/reset' do
            ::Services::CircuitBreakerService.reset_all
            json({ message: 'All circuit breakers reset', status: 'success' })
          end

          # Conversation analytics endpoint
          app.get '/api/v1/analytics/conversations' do
            content_type :json

            limit = params[:limit]&.to_i || 10
            history = GlitchCube::Persistence.get_conversation_history(limit: limit)

            json({
                   success: true,
                   count: history.length,
                   conversations: history
                 })
          end

          # System prompt preview endpoint
          app.get '/api/v1/system_prompt/:character?' do
            content_type :json

            require_relative '../../services/system_prompt_service'

            character = params[:character]
            context = {
              location: params[:location] || 'Default Location',
              battery_level: params[:battery] || '100%',
              interaction_count: params[:count]&.to_i || 1
            }

            prompt_service = ::Services::SystemPromptService.new(
              character: character,
              context: context
            )

            json({
                   success: true,
                   character: character || 'default',
                   prompt: prompt_service.generate,
                   timestamp: Time.now.iso8601
                 })
          end

          # Module analytics endpoint
          app.get '/api/v1/analytics/modules/:module_name' do
            content_type :json

            analytics = GlitchCube::Persistence.get_module_analytics(params[:module_name])

            json({
                   success: true,
                   module: params[:module_name],
                   analytics: analytics
                 })
          end

          # Context document management endpoints
          app.get '/api/v1/context/documents' do
            content_type :json

            require_relative '../../services/context_retrieval_service'
            service = ::Services::ContextRetrievalService.new

            json({
                   success: true,
                   documents: service.list_documents
                 })
          end

          app.post '/api/v1/context/documents' do
            content_type :json

            begin
              data = JSON.parse(request.body.read)

              require_relative '../../services/context_retrieval_service'
              service = ::Services::ContextRetrievalService.new

              success = service.add_document(
                data['filename'],
                data['content'],
                data['metadata'] || {}
              )

              json({
                     success: success,
                     message: success ? 'Document added successfully' : 'Failed to add document'
                   })
            rescue StandardError => e
              status 400
              json({
                     success: false,
                     error: e.message
                   })
            end
          end

          # Test context retrieval
          app.post '/api/v1/context/search' do
            content_type :json

            begin
              data = JSON.parse(request.body.read)

              require_relative '../../services/context_retrieval_service'
              service = ::Services::ContextRetrievalService.new

              results = service.retrieve_context(data['query'], k: data['k'] || 3)

              json({
                     success: true,
                     query: data['query'],
                     results: results
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
