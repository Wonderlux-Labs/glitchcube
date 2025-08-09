# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Simple Admin Interface' do
  describe 'GET /admin/simple' do
    it 'loads the simple admin page', :vcr do
      get '/admin/simple'

      expect(last_response).to be_ok
      expect(last_response.body).to include('GLITCH CUBE ADMIN - SIMPLE')
    end

    it 'includes basic conversation form', :vcr do
      get '/admin/simple'

      expect(last_response.body).to include('Conversation Test')
      expect(last_response.body).to include('Send Message')
      expect(last_response.body).to include('persona')
    end

    it 'has basic JavaScript functions', :vcr do
      get '/admin/simple'

      # Should have these basic functions
      expect(last_response.body).to include('sendMessage()')
      expect(last_response.body).to include('clearDisplay()')

      # Should have memory functions (simple includes memory management)
      expect(last_response.body).to include('loadMemories')

      # Should NOT have advanced tab switching from advanced version
      expect(last_response.body).not_to include('switchMemoryTab')
    end
  end

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
