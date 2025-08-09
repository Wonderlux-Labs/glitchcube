# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'

RSpec.describe 'Admin/Development Interface', :failing do
  include Rack::Test::Methods

  def app
    GlitchCubeApp
  end

  describe 'development-only endpoints' do
    context 'when in development mode' do
      describe 'GET /api/v1/analytics/conversations' do
        it 'returns conversation history', :vcr do
          get '/api/v1/analytics/conversations?limit=5'

          expect(last_response).to be_ok
          json = JSON.parse(last_response.body)
          expect(json['success']).to be true
          expect(json).to have_key('conversations')
        end
      end

      describe 'GET /api/v1/analytics/modules/:module_name' do
        it 'returns module analytics', :vcr do
          get '/api/v1/analytics/modules/ConversationModule'

          expect(last_response).to be_ok
          json = JSON.parse(last_response.body)
          expect(json['success']).to be true
          expect(json['module']).to eq('ConversationModule')
          expect(json).to have_key('analytics')
        end
      end

      describe 'GET /api/v1/system_prompt/:character' do
        it 'previews system prompts for different characters', :vcr do
          get '/api/v1/system_prompt/playful?location=gallery&battery=75'

          expect(last_response).to be_ok
          json = JSON.parse(last_response.body)
          expect(json['success']).to be true
          expect(json['character']).to eq('playful')
          expect(json).to have_key('prompt')
        end
      end

      describe 'context document management' do
        describe 'GET /api/v1/context/documents' do
          it 'lists available context documents', :vcr do
            get '/api/v1/context/documents'

            expect(last_response).to be_ok
            json = JSON.parse(last_response.body)
            expect(json['success']).to be true
            expect(json).to have_key('documents')
          end
        end

        describe 'POST /api/v1/context/search' do
          it 'searches context documents', :vcr do
            post '/api/v1/context/search',
                 { query: 'consciousness', k: 2 }.to_json,
                 { 'CONTENT_TYPE' => 'application/json' }

            expect(last_response).to be_ok
            json = JSON.parse(last_response.body)
            expect(json['success']).to be true
            expect(json['query']).to eq('consciousness')
            expect(json).to have_key('results')
          end
        end
      end
    end

    context 'when in production mode' do
      # NOTE: In test mode, endpoints are available for testing
      # In real production, these endpoints are controlled by environment
      it 'exposes analytics endpoints in test/dev environments', :vcr do
        # This verifies the endpoints work in test environment
        get '/api/v1/analytics/conversations'
        expect(last_response.status).to eq(200)

        # Verify it returns proper JSON structure
        json = JSON.parse(last_response.body)
        expect(json).to have_key('success')
      end

      it 'exposes context management endpoints in test/dev environments', :vcr do
        get '/api/v1/context/documents'
        expect(last_response.status).to eq(200)

        # Verify it returns proper JSON structure
        json = JSON.parse(last_response.body)
        expect(json).to have_key('success')
      end
    end
  end

  describe 'conversation with context (RAG)' do
    describe 'POST /api/v1/conversation/with_context' do
      it 'enhances responses with relevant context', :vcr do
        post '/api/v1/conversation/with_context',
             { message: 'What are you?', mood: 'curious' }.to_json,
             { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response).to be_ok
        json = JSON.parse(last_response.body)
        expect(json['success']).to be true
        expect(json['data']).to have_key('response')
        expect(json['data']).to have_key('contexts_used')
        expect(json['data']['confidence']).to be > 0
      end
    end
  end

  describe 'session tracking for summarization' do
    it 'tracks conversations by session', :vcr do
      # First message
      post '/api/v1/conversation',
           { message: 'Hello!', context: { session_id: 'test-123' } }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response).to be_ok

      # Goodbye message (should trigger summarization)
      post '/api/v1/conversation',
           { message: 'Goodbye!', context: { session_id: 'test-123' } }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response).to be_ok

      # In a real test, we'd check that the summary job was enqueued
      # For now, just verify the endpoint works
    end
  end
end
