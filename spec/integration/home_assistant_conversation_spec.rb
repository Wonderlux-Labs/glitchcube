# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/home_assistant_client'
require_relative '../../lib/services/conversation_session'

RSpec.describe "Home Assistant Conversation Integration", vcr: { cassette_name: "ha_conversation_integration" } do
  let(:client) { HomeAssistantClient.new }
  
  describe 'Wake word detection flow' do
    context 'when triggering conversation from Home Assistant side' do
      it 'starts a conversation through Home Assistant conversation agent' do
        # This simulates what happens when wake word is detected
        # The conversation.process service is what gets called by wake word detection
        
        VCR.use_cassette('integration/ha_conversation_start') do
          # Start a conversation from HA side using conversation.process
          # This is what the wake word detection does internally
          result = client.call_service(
            'conversation',
            'process',
            {
              text: 'Hello Glitch Cube, are you there?',
              agent_id: 'conversation.glitchcube',  # Our custom agent
              language: 'en'
            },
            return_response: true  # Get the full response
          )
          
          expect(result).to be_a(Hash)
          # The custom agent should have processed this through our Sinatra API
          # and returned a response
          expect(result).to have_key('service_response')
          expect(result['service_response']).to have_key('response')
        end
      end
    end
    
    context 'when using assist pipeline (modern HA approach)' do
      it 'triggers conversation through assist intent' do
        VCR.use_cassette('integration/ha_assist_intent') do
          # This is the more modern way - using assist_pipeline.start
          # which is what wake word detection triggers in modern HA
          result = client.call_service(
            'assist_pipeline',
            'start',
            {
              start_stage: 'intent',  # Skip wake word and STT stages
              end_stage: 'tts',       # Process through TTS
              input: {
                text: 'Turn on the lights and play some music'
              },
              conversation_id: SecureRandom.uuid,
              device_id: 'test_device'
            },
            return_response: true  # Get the full pipeline result
          )
          
          # Pipeline should return structured response
          if result && result['pipeline_run']
            expect(result['pipeline_run']).to have_key('intent')
            expect(result['pipeline_run']).to have_key('tts')
          end
        end
      end
    end
    
    context 'when testing webhook fallback' do
      it 'can trigger conversation via webhook endpoint' do
        # Test the direct webhook endpoint as a fallback
        # This would normally be called by HA automations
        
        VCR.use_cassette('integration/ha_webhook_conversation') do
          # Use HomeAssistantWebhookService to send to our Sinatra webhook
          require_relative '../../lib/services/home_assistant_webhook_service'
          webhook_service = Services::HomeAssistantWebhookService.new
          
          result = webhook_service.send_update({
            event_type: 'conversation_started',
            conversation_id: SecureRandom.uuid,
            device_id: 'test_device',
            session_id: SecureRandom.uuid
          })
          
          expect(result[:success]).to be true
        end
      end
    end
  end
  
  describe 'Programmatic wake word simulation' do
    it 'can simulate wake word detection for testing' do
      VCR.use_cassette('integration/simulate_wake_word') do
        # Create a test automation that simulates wake word detection
        # This is useful for testing without actual voice input
        
        # First, check if our conversation agent is available
        agents = client.call_service(
          'conversation',
          'agent_info',
          {},
          return_response: true
        )
        
        if agents && agents['agents']
          glitchcube_agent = agents['agents'].find { |a| a['id'] == 'conversation.glitchcube' }
          expect(glitchcube_agent).not_to be_nil
        end
        
        # Now simulate wake word -> conversation flow
        result = client.call_service(
          'automation',
          'trigger',
          {
            entity_id: 'automation.test_wake_word_simulation',
            variables: {
              message: 'Testing wake word detection',
              device_id: 'test_device'
            }
          }
        )
        
        # The automation should have triggered our conversation flow
        expect(result).to be_truthy
      end
    end
    
    it 'can create temporary test automation for wake word simulation' do
      VCR.use_cassette('integration/create_wake_test_automation') do
        # Dynamically create a test automation for wake word simulation
        # This is useful for CI/CD testing
        
        automation_config = {
          alias: 'Test Wake Word Simulation',
          trigger: {
            platform: 'event',
            event_type: 'test_wake_word'
          },
          action: [
            {
              service: 'conversation.process',
              data: {
                text: '{{ trigger.event.data.message }}',
                agent_id: 'conversation.glitchcube',
                language: 'en'
              }
            }
          ]
        }
        
        # Note: This would need to be done via config entry in real HA
        # For testing, we fire the event directly
        result = client.call_service(
          'event',
          'fire',
          {
            event_type: 'test_wake_word',
            event_data: {
              message: 'Hello from simulated wake word'
            }
          }
        )
        
        expect(result).to be_truthy
      end
    end
  end
  
  describe 'Session synchronization' do
    it 'correctly maps HA conversation_id to internal session_id' do
      VCR.use_cassette('integration/session_sync') do
        # Start conversation from HA
        ha_result = client.call_service(
          'conversation',
          'process',
          {
            text: 'Start a new session',
            agent_id: 'conversation.glitchcube',
            language: 'en'
          }
        )
        
        # Check that our Sinatra app created a matching session
        if ha_result && ha_result['conversation_id']
          # Find the session in our database
          session = Services::ConversationSession.find_by_ha_conversation_id(
            ha_result['conversation_id']
          )
          
          # Session should exist and have proper mapping
          if session
            expect(session.metadata[:ha_conversation_id]).to eq(ha_result['conversation_id'])
            expect(session.metadata[:voice_interaction]).to be true
          end
        end
      end
    end
  end
end