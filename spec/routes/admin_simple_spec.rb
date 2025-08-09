# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Admin API Endpoints' do
  # NOTE: The /admin/simple and /admin/advanced interfaces were consolidated into /admin

  describe 'POST /admin/proactive_conversation' do
    it 'creates a conversation session with proactive message', :vcr do
      post '/admin/proactive_conversation',
           { character: 'buddy' }.to_json,
           { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response).to be_ok

      body = JSON.parse(last_response.body)
      expect(body['success']).to be true
      expect(body['session_id']).to start_with('proactive_')
      expect(body['character']).to eq('buddy')
      expect(body['message']).to be_a(String)
    end
  end

  describe 'GET /admin/status' do
    it 'returns system status', :vcr do
      get '/admin/status'

      expect(last_response).to be_ok

      body = JSON.parse(last_response.body)
      expect(body).to have_key('home_assistant')
      expect(body).to have_key('openrouter')
      expect(body).to have_key('redis')
      expect(body).to have_key('ai_model')
    end
  end
end
