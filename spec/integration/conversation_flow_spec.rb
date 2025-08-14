# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Conversation Flow', type: :integration, VCR: true do
  include_context 'with_full_conversation_setup'

  let(:conversation_service) { ConversationModule.new }

  describe 'simple conversation without tool calls' do
    it 'returns a simple text response' do
      user_message = 'Hello, how are you?'
      context = { session_id: 'integration-test-session' }

      VCR.use_cassette('simple_conversation') do
        response = conversation_service.call(message: user_message, context: context)

        expect(response).to be_a_valid_conversation_response
        expect(response[:response]).to be_a(String)
        expect(response[:response]).not_to be_empty
        expect(response[:session_id]).to be_a(String)
      end
    end
  end

  describe 'conversation with tool calls' do
    it 'correctly calls a tool and returns the result' do
      user_message = "What's the weather in San Francisco?"
      context = { session_id: 'tool-test-session', tools: [] }

      VCR.use_cassette('conversation_with_tool_call') do
        response = conversation_service.call(message: user_message, context: context)

        expect(response).to be_a_valid_conversation_response
        expect(response[:response]).to be_a(String)
        expect(response[:response]).not_to be_empty
        expect(response[:session_id]).to be_a(String)
      end
    end
  end

  describe 'handling tool execution errors' do
    it 'returns a user-friendly error message' do
      user_message = 'Trigger a failing tool'
      context = { session_id: 'error-test-session' }

      VCR.use_cassette('conversation_with_tool_error') do
        response = conversation_service.call(message: user_message, context: context)

        expect(response).to be_a_valid_conversation_response
        expect(response[:response]).to be_a(String)
        expect(response[:response]).not_to be_empty
        expect(response[:session_id]).to be_a(String)
      end
    end
  end

  describe 'handling invalid LLM responses' do
    it 'handles malformed JSON from the LLM' do
      user_message = 'Ask something that returns malformed JSON'
      context = { session_id: 'invalid-response-session' }

      VCR.use_cassette('conversation_with_invalid_llm_response') do
        response = conversation_service.call(message: user_message, context: context)

        expect(response).to be_a_valid_conversation_response
        expect(response[:response]).to be_a(String)
        expect(response[:response]).not_to be_empty
        expect(response[:session_id]).to be_a(String)
      end
    end
  end

  describe 'conversation context preservation' do
    it 'maintains session context across calls' do
      context = { session_id: 'context-preservation-test' }

      VCR.use_cassette('simple_conversation') do
        first_response = conversation_service.call(message: 'Hello', context: context)
        second_response = conversation_service.call(message: 'Follow up', context: context)

        expect(first_response[:session_id]).to eq(second_response[:session_id])
        expect(first_response).to be_a_valid_conversation_response
        expect(second_response).to be_a_valid_conversation_response
      end
    end
  end
end
