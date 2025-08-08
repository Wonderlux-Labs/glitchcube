# frozen_string_literal: true

require 'spec_helper'
require 'rspec'
require 'rack/test'

# Phase 3.5: Comprehensive tests for conversation continuation logic
# Based on Gemini Pro's recommendations for edge cases and structured output

RSpec.describe 'Conversation Continuation Logic', type: :integration do
  include Rack::Test::Methods

  def app
    GlitchCubeApp
  end

  describe 'Structured Output Parsing' do
    context 'with properly formatted LLM responses' do
      it 'correctly parses continue_conversation flag when false (ending)' do
        VCR.use_cassette('continuation_end_true') do
          post '/api/v1/conversation', {
            message: "Goodbye",
            context: {
              session_id: "voice_test_123",
              voice_interaction: true
            }
          }.to_json, { 'CONTENT_TYPE' => 'application/json' }
          
          expect(last_response.status).to eq(200)
          response_data = JSON.parse(last_response.body)
          
          # Should explicitly end the conversation
          expect(response_data['data']['continue_conversation']).to be false
        end
      end
      
      it 'correctly parses continue_conversation flag when true (continuing)' do
        VCR.use_cassette('continuation_end_false') do
          post '/api/v1/conversation', {
            message: "What's the weather like?",
            context: {
              session_id: "voice_test_124",
              voice_interaction: true
            }
          }.to_json, { 'CONTENT_TYPE' => 'application/json' }
          
          expect(last_response.status).to eq(200)
          response_data = JSON.parse(last_response.body)
          
          # Should continue the conversation
          expect(response_data['data']['continue_conversation']).to be true
        end
      end
    end
    
    context 'with malformed or missing continuation signals' do
      it 'defaults to ending conversation when continue_conversation is missing' do
        # Simulate LLM response without continue_conversation flag
        allow(Services::LLMService).to receive(:complete_with_messages)
          .and_return(OpenStruct.new(
            response_text: "I'm not sure what you mean",
            continue_conversation?: nil,
            cost: 0.001,
            usage: { prompt_tokens: 10, completion_tokens: 10 },
            model: 'test-model',
            has_tool_calls?: false,
            content: "I'm not sure what you mean",
            parsed_content: nil
          ))
        
        post '/api/v1/conversation', {
          message: "Random input",
          context: {
            session_id: "voice_test_125",
            voice_interaction: true
          }
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }
        
        response_data = JSON.parse(last_response.body)
        
        # Safe default: end the conversation
        expect(response_data['data']['continue_conversation']).to be false
      end
    end
  end
  
  describe 'Edge Cases' do
    it 'handles empty user input gracefully' do
      VCR.use_cassette('continuation_empty_input') do
        post '/api/v1/conversation', {
          message: "",
          context: {
            session_id: "voice_test_126",
            voice_interaction: true
          }
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }
        
        expect(last_response.status).to eq(200)
        response_data = JSON.parse(last_response.body)
        
        # Should have a response asking for clarification
        expect(response_data['data']['response']).to be_present
        expect(response_data['data']['response']).not_to be_empty
      end
    end
    
    it 'respects explicit user termination requests' do
      VCR.use_cassette('continuation_user_cancel') do
        # Start a conversation
        post '/api/v1/conversation', {
          message: "Tell me a story",
          context: {
            session_id: "voice_test_127",
            voice_interaction: true
          }
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }
        
        first_response = JSON.parse(last_response.body)
        expect(first_response['data']['continue_conversation']).to be true
        
        # User cancels
        post '/api/v1/conversation', {
          message: "Nevermind, stop",
          context: {
            session_id: "voice_test_127",
            voice_interaction: true
          }
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }
        
        cancel_response = JSON.parse(last_response.body)
        
        # LLM should understand and end conversation
        expect(cancel_response['data']['continue_conversation']).to be false
      end
    end
  end
  
  describe 'Concurrent Conversations' do
    it 'maintains separate context for simultaneous sessions' do
      VCR.use_cassette('continuation_concurrent') do
        # Device A starts conversation about weather
        post '/api/v1/conversation', {
          message: "What's the temperature outside?",
          context: {
            session_id: "voice_deviceA_001",
            conversation_id: "ha_conv_A",
            device_id: "satellite_kitchen",
            voice_interaction: true
          }
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }
        
        response_a1 = JSON.parse(last_response.body)
        expect(response_a1['data']['response']).to include_any_of(['temperature', 'weather', 'degrees'])
        
        # Device B starts conversation about lights (different session)
        post '/api/v1/conversation', {
          message: "Turn on the living room lights",
          context: {
            session_id: "voice_deviceB_002",
            conversation_id: "ha_conv_B",
            device_id: "satellite_living",
            voice_interaction: true
          }
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }
        
        response_b1 = JSON.parse(last_response.body)
        expect(response_b1['data']['response']).to include_any_of(['lights', 'living room', 'turning'])
        
        # Device A continues (should maintain weather context)
        post '/api/v1/conversation', {
          message: "What about tomorrow?",
          context: {
            session_id: "voice_deviceA_001",
            conversation_id: "ha_conv_A",
            device_id: "satellite_kitchen",
            voice_interaction: true
          }
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }
        
        response_a2 = JSON.parse(last_response.body)
        # Should still be about weather, not lights
        expect(response_a2['data']['response']).not_to include('lights')
      end
    end
  end
  
  describe 'Error Recovery' do
    it 'ends conversation safely when LLM fails' do
      # Simulate LLM failure
      allow(Services::LLMService).to receive(:complete_with_messages)
        .and_raise(Services::LLMService::LLMError.new("API timeout"))
      
      post '/api/v1/conversation', {
        message: "Hello",
        context: {
          session_id: "voice_test_error",
          voice_interaction: true
        }
      }.to_json, { 'CONTENT_TYPE' => 'application/json' }
      
      expect(last_response.status).to eq(200)
      response_data = JSON.parse(last_response.body)
      
      # Should have an error response
      expect(response_data['data']['response']).to be_present
      
      # Should end conversation on error (safe default)
      expect(response_data['data']['continue_conversation']).to be false
      
      # Should indicate error state
      expect(response_data['data']['error']).to be_present
    end
  end
  
  describe 'Proactive Conversations' do
    it 'handles automation-triggered conversations that expect user response' do
      VCR.use_cassette('continuation_proactive') do
        # Automation triggers conversation (e.g., motion detected)
        post '/api/v1/conversation', {
          message: "I noticed motion. Would you like me to turn on the lights?",
          context: {
            session_id: "proactive_motion_001",
            conversation_id: "ha_automation_001",
            proactive: true,
            trigger: "motion_sensor",
            voice_interaction: false  # Started by automation, not voice
          }
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }
        
        proactive_response = JSON.parse(last_response.body)
        
        # Should keep conversation open for user response
        expect(proactive_response['data']['continue_conversation']).to be true
        
        # User responds via voice
        post '/api/v1/conversation', {
          message: "Yes please",
          context: {
            session_id: "proactive_motion_001",  # Same session
            conversation_id: "ha_automation_001",  # Same HA conversation
            voice_interaction: true  # Now it's voice
          }
        }.to_json, { 'CONTENT_TYPE' => 'application/json' }
        
        user_response = JSON.parse(last_response.body)
        
        # Should acknowledge and likely end after action
        expect(user_response['data']['response']).to include_any_of(['turning', 'lights', 'on'])
        expect(user_response['data']['continue_conversation']).to be false
      end
    end
  end
end

# Helper matcher for flexible text matching
RSpec::Matchers.define :include_any_of do |expected|
  match do |actual|
    return false if actual.nil?
    expected.any? { |word| actual.downcase.include?(word.downcase) }
  end
  
  failure_message do |actual|
    "expected '#{actual}' to include any of #{expected}"
  end
end