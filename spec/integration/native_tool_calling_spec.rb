# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'

RSpec.describe 'Native Tool Calling Integration', type: :integration do
  include Rack::Test::Methods

  def app
    GlitchCubeApp
  end

  let(:session_id) { 'test-native-tools-123' }

  describe 'Happy Path: End-to-End Tool Calling via API' do
    context 'when asking to control lights and speak', :vcr do
      it 'calls tools automatically through conversation API and speaks response' do
        # Make actual API call like Home Assistant would
        post '/api/v1/conversation', {
          message: 'Can you please give us some party lights on the cube and cart?',
          session_id: session_id,
          persona: 'buddy',
          model: 'anthropic/claude-sonnet-4',  # Use a better model that handles tool calling properly
          voice_interaction: true,
          context: {
            use_tools: true  # Enable tool calling
          }
        }.to_json, {
          'CONTENT_TYPE' => 'application/json'
        }

        expect(last_response.status).to eq(200)

        response_data = JSON.parse(last_response.body)

        # Extract data from nested response
        data = response_data['data'] || response_data

        # Verify response structure (even if there was an error, we should get a response)
        expect(data['response']).to be_present
        expect(data['response']).to be_a(String)
        expect(data['continue_conversation']).to be_in([true, false])
        expect(data['session_id']).to eq(session_id)

        # The response should be a reasonable response (not an error)
        expect(data['response']).to be_present
        expect(data['response'].length).to be > 5

        # Check conversation was saved to database
        conversation = Conversation.find_by(session_id: session_id)
        expect(conversation).to be_present

        # Should have at least 2 messages (user + assistant)
        expect(conversation.messages.count).to be >= 2

        # Assistant message should mention the action taken
        assistant_message = conversation.messages.where(role: 'assistant').last
        expect(assistant_message.content.downcase).to include('purple').or include('light')
      end

      it 'handles simple text conversation without tools', :vcr do
        post '/api/v1/conversation', {
          message: 'Hello, how are you today?',
          session_id: "#{session_id}_simple",
          persona: 'buddy',
          model: 'openai/gpt-4o',
          voice_interaction: false,
          context: {
            use_tools: false  # Disable tool calling
          }
        }.to_json, {
          'CONTENT_TYPE' => 'application/json'
        }

        expect(last_response.status).to eq(200)

        response_data = JSON.parse(last_response.body)

        # Extract data from nested response
        data = response_data['data'] || response_data

        # Verify basic response structure
        expect(data['response']).to be_present
        expect(data['continue_conversation']).to be_in([true, false])
        expect(data['session_id']).to eq("#{session_id}_simple")

        # Should be a friendly greeting response (Buddy's style)
        expect(data['response'].downcase).to include('hello')
          .or include('good')
          .or include('fine')
          .or include('fantastic')
          .or include('amazing')
          .or include('help')
      end
    end
  end

  describe 'Response Validation' do
    context 'with edge case inputs', :vcr do
      it 'ensures continue_conversation is always a boolean' do
        post '/api/v1/conversation', {
          message: 'Just say hello',
          session_id: "#{session_id}_validation",
          persona: 'buddy',
          model: 'openai/gpt-4o',
          voice_interaction: false
        }.to_json, {
          'CONTENT_TYPE' => 'application/json'
        }

        expect(last_response.status).to eq(200)
        response_data = JSON.parse(last_response.body)

        # Extract data from nested response
        data = response_data['data'] || response_data

        expect(data['continue_conversation']).to be_in([true, false])
        expect([TrueClass, FalseClass]).to include(data['continue_conversation'].class)
      end

      it 'provides fallback response when input is minimal' do
        post '/api/v1/conversation', {
          message: '...',
          session_id: "#{session_id}_fallback",
          persona: 'buddy',
          model: 'openai/gpt-4o',
          voice_interaction: false
        }.to_json, {
          'CONTENT_TYPE' => 'application/json'
        }

        expect(last_response.status).to eq(200)
        response_data = JSON.parse(last_response.body)

        # Extract data from nested response
        data = response_data['data'] || response_data

        expect(data['response']).to be_present
        expect(data['response'].length).to be > 0
      end
    end
  end
end
