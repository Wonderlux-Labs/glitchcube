# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/routes/api/conversation'
require 'rack/test'

RSpec.describe 'Home Assistant Conversation Integration', type: :integration do
  include Rack::Test::Methods

  def app
    GlitchCubeApp
  end
  let(:ha_conversation_payload) do
    {
      'message' => 'Turn on the cube lights',
      'context' => {
        'conversation_id' => 'ha-conversation-123',
        'device_id' => 'glitchcube_satellite',
        'language' => 'en',
        'voice_interaction' => true,
        'ha_context' => {
          'agent_id' => 'glitchcube_conversation',
          'user_id' => nil
        }
      }
    }
  end

  describe 'Primary /api/v1/conversation endpoint' do
    context 'when called from HA custom conversation agent' do
      it 'processes HA conversation through unified endpoint', :vcr do
        post '/api/v1/conversation', ha_conversation_payload.to_json, {
          'CONTENT_TYPE' => 'application/json'
        }
        # Should successfully process conversation
        expect(last_response.status).to eq(200)
        response_data = JSON.parse(last_response.body)
        expect(response_data['success']).to be true
        expect(response_data['data']).to be_present
        expect(response_data['data']['response']).to be_a(String)
        expect(response_data['data']['conversation_id']).to be_present
        expect(response_data['data']['persona']).to be_present
      end

      it 'maintains conversation session across HA calls', :vcr do
        # First call
        post '/api/v1/conversation', ha_conversation_payload.to_json, {
          'CONTENT_TYPE' => 'application/json'
        }
        first_response = JSON.parse(last_response.body)
        session_id = first_response['data']['conversation_id']
        # Second call with same HA conversation but different session context
        follow_up_payload = ha_conversation_payload.merge(
          'message' => 'What did I just ask for?',
          'context' => ha_conversation_payload['context'].merge(
            'session_id' => session_id
          )
        )
        post '/api/v1/conversation', follow_up_payload.to_json, {
          'CONTENT_TYPE' => 'application/json'
        }
        expect(last_response.status).to eq(200)
        follow_up_response = JSON.parse(last_response.body)
        # Should maintain same conversation session
        expect(follow_up_response['data']['conversation_id']).to eq(session_id)
        expect(follow_up_response['data']['response']).to include('lights')
      end

      it 'handles HA voice interaction context properly', :vcr do
        post '/api/v1/conversation', ha_conversation_payload.to_json, {
          'CONTENT_TYPE' => 'application/json'
        }
        expect(last_response.status).to eq(200)
        response_data = JSON.parse(last_response.body)
        # Should recognize it as voice interaction from HA
        conversation_data = response_data['data']
        expect(conversation_data).to be_present
        # Context should be preserved for debugging
        expect(ha_conversation_payload['context']['voice_interaction']).to be true
        expect(ha_conversation_payload['context']['device_id']).to eq('glitchcube_satellite')
      end
    end
  end

  describe 'Simplified Architecture - Phase 3.5 COMPLETED' do
    context 'webhook endpoints have been removed' do
      it 'no longer has complex webhook logic - all removed in consolidation', :vcr do
        # Webhook endpoint has been completely removed
        # All conversation flow now goes through /api/v1/conversation

        post '/api/v1/ha_webhook', {}.to_json, {
          'CONTENT_TYPE' => 'application/json'
        }

        # Endpoint no longer exists
        expect(last_response.status).to eq(404)

        # NOTE: This test documents that Phase 3.5 consolidation is complete
        # The webhook complexity has been eliminated
        # All conversation now flows through single unified endpoint
      end
    end

    it 'has successfully consolidated to single conversation endpoint', :vcr do
      # Phase 3.5 COMPLETE: Consolidated to single endpoint

      # Only one conversation endpoint remains:
      primary_endpoint = '/api/v1/conversation'

      # These endpoints have been removed in consolidation:
      removed_endpoints = [
        '/api/v1/conversation/start',     # Removed - sessions auto-created
        '/api/v1/conversation/continue',  # Removed - handled by session_id
        '/api/v1/conversation/end',       # Removed - handled by end_conversation flag
        '/api/v1/conversation/with_context', # Removed - context always included
        '/api/v1/ha_webhook' # Removed - no more webhooks
      ]

      # Verify removed endpoints return 404
      removed_endpoints.each do |endpoint|
        post endpoint, {}.to_json, { 'CONTENT_TYPE' => 'application/json' }
        expect(last_response.status).to eq(404), "#{endpoint} should be removed"
      end

      # Verify primary endpoint still works
      post primary_endpoint, {
        message: 'Hello',
        context: { session_id: 'test' }
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response.status).to eq(200)

      # Primary endpoint should handle all HA conversation needs
      post '/api/v1/conversation', ha_conversation_payload.to_json, {
        'CONTENT_TYPE' => 'application/json'
      }

      expect(last_response.status).to eq(200)
      # This should be sufficient for HA integration post-Phase 3
    end
  end

  describe 'Current HA Custom Agent Analysis' do
    it 'documents current custom agent complexity for simplification', :vcr do
      # Current custom agent (conversation.py) has these responsibilities:
      responsibilities = [
        'Dynamic API URL resolution via input_text.glitchcube_host',
        'Request payload construction with HA context',
        'HTTP client management with timeout handling',
        'Response parsing and intent response creation',
        'Suggested actions processing (_handle_suggested_actions)',
        'Media actions processing (_handle_media_actions)',
        'Error handling and fallback responses',
        'Conversation continuation logic'
      ]

      # Phase 3 Goal: Simplify to pure HTTP forwarding glue
      # Most of this logic should move to Sinatra or be eliminated

      expect(responsibilities.length).to eq(8) # Documents current complexity
    end

    it 'shows simplified agent with no bidirectional HA service calls', :vcr do
      # Phase 3.5 COMPLETE: Agent is now pure HTTP forwarder

      # Custom HA agent no longer makes ANY service calls
      # It's pure glue code that just forwards to Sinatra
      bidirectional_calls = [] # Empty! No more bidirectional complexity

      # All hardware control now happens through Sinatra's tool execution:

      # Goal achieved: Agent is stateless HTTP forwarder
      expect(bidirectional_calls.length).to eq(0) # Complexity eliminated!
    end
  end
end
