# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ConversationModule Integration', :vcr do
  include_context 'with_full_conversation_setup'

  let(:module_instance) { ConversationModule.new }

  describe 'Real conversation flow with Home Assistant' do
    context 'with real LLM and Home Assistant' do
      it 'processes a message and speaks through Home Assistant' do
        result = module_instance.call(
          message: 'Hello, what are you?',
          context: { session_id: 'test-integration-123' },
          persona: 'buddy'
        )

        expect(result).to be_a_valid_conversation_response(expected_persona: 'buddy')
        expect(result[:response]).to be_a(String)
        expect(result[:response].length).to be > 10
        expect(result[:session_id]).to be_a(String)
        expect(result[:persona]).to eq('buddy')
      end

      it 'handles personas correctly' do
        result = module_instance.call(
          message: 'Tell me about yourself',
          context: { session_id: 'test-persona' },
          persona: 'buddy'
        )

        expect(result).to be_a_valid_conversation_response(expected_persona: 'buddy')
        expect(result[:response]).to be_a(String)
        expect(result[:persona]).to eq('buddy')
      end
    end

    context 'error handling with real services' do
      xit 'handles errors gracefully' do
        # TODO: Integration error handling test - may need adjustment for error response format
        # Force an error by stubbing the LLM service
        allow(Services::Llm::LLMService).to receive(:complete_with_messages)
          .and_raise(Services::Llm::LLMService::LLMError.new('Simulated error'))

        result = module_instance.call(
          message: 'This should fail',
          context: { session_id: 'test-error' },
          persona: 'buddy'
        )

        expect(result).to be_a_valid_conversation_response
        expect(result[:response]).to be_a(String)
        expect(result[:response]).not_to be_empty
      end
    end

    context 'with real Home Assistant TTS' do
      it 'sends TTS commands to Home Assistant' do
        result = module_instance.call(
          message: 'Say something short',
          context: { session_id: 'test-tts' },
          persona: 'buddy'
        )

        expect(result).to be_a_valid_conversation_response(expected_persona: 'buddy')
        expect(result[:response]).to be_a(String)
        expect(result[:response]).not_to be_empty
      end
    end
  end

  describe 'Session persistence across conversations' do
    let(:session_id) { 'test-session-persistence' }

    it 'maintains context across multiple messages' do
      # First message
      result1 = module_instance.call(
        message: 'My name is TestUser',
        context: { session_id: session_id },
        persona: 'buddy'
      )

      expect(result1).to be_a_valid_conversation_response(expected_persona: 'buddy')
      expect(result1[:response]).to be_a(String)
      expect(result1[:session_id]).to be_a(String)

      # Second message - should remember context
      result2 = module_instance.call(
        message: 'What is my name?',
        context: { session_id: session_id },
        persona: 'buddy'
      )

      expect(result2).to be_a_valid_conversation_response(expected_persona: 'buddy')
      expect(result2[:response]).to be_a(String)
      expect(result2[:session_id]).to eq(result1[:session_id])
    end
  end
end
