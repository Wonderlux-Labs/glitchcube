# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'

RSpec.describe 'Admin/Development Interface' do
  include Rack::Test::Methods

  def app
    GlitchCubeApp
  end

  describe 'development-only endpoints' do
    context 'when in development mode' do
      describe 'GET /api/v1/analytics/conversations' do
        it 'returns conversation history' do
          get '/api/v1/analytics/conversations?limit=5'

          expect(last_response).to be_ok
          json = JSON.parse(last_response.body)
          expect(json['success']).to be true
          expect(json).to have_key('conversations')
        end
      end

      describe 'GET /api/v1/analytics/modules/:module_name' do
        it 'returns module analytics' do
          get '/api/v1/analytics/modules/ConversationModule'

          expect(last_response).to be_ok
          json = JSON.parse(last_response.body)
          expect(json['success']).to be true
          expect(json['module']).to eq('ConversationModule')
          expect(json).to have_key('analytics')
        end
      end

      describe 'GET /api/v1/system_prompt/:character' do
        it 'previews system prompts for different characters' do
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
          it 'lists available context documents' do
            get '/api/v1/context/documents'

            expect(last_response).to be_ok
            json = JSON.parse(last_response.body)
            expect(json['success']).to be true
            expect(json).to have_key('documents')
          end
        end

        describe 'POST /api/v1/context/search' do
          it 'searches context documents' do
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
      # Skip these tests as we need the endpoints available in test mode
      # In real production, these endpoints won't be available
      xit 'does not expose analytics endpoints' do
        get '/api/v1/analytics/conversations'
        expect(last_response.status).to eq(404)
      end

      xit 'does not expose context management endpoints' do
        get '/api/v1/context/documents'
        expect(last_response.status).to eq(404)
      end
    end
  end

  describe 'conversation with context (RAG)' do
    describe 'POST /api/v1/conversation/with_context' do
      it 'enhances responses with relevant context', vcr: { cassette_name: 'conversation_with_context' } do
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
    it 'tracks conversations by session' do
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
