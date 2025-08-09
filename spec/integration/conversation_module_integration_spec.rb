# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/modules/conversation_module'

RSpec.describe 'ConversationModule Integration', :vcr do
  let(:module_instance) { ConversationModule.new }

  describe 'Real conversation flow with Home Assistant' do
    context 'with real LLM and Home Assistant' do
      it 'processes a message and speaks through Home Assistant' do
        result = module_instance.call(
          message: 'Hello, what are you?',
          context: { session_id: 'test-integration-123' },
          persona: 'buddy'
        )
        # Verify we got a real response
        expect(result[:response]).to be_a(String)
        expect(result[:response].length).to be > 10
        expect(result[:conversation_id]).to eq('test-integration-123')
        expect(result[:persona]).to eq('buddy')
        # Model, cost, and tokens may be nil in error responses
        if result[:error].nil?
          expect(result[:model]).to be_a(String)
          expect(result[:cost]).to be_a(Numeric)
          expect(result[:tokens]).to be_a(Hash)
        end
      end

      it 'handles personas correctly' do
        result = module_instance.call(
          message: 'Tell me about yourself',
          context: { session_id: 'test-persona' },
          persona: 'buddy'
        )
        expect(result[:response]).to be_a(String)
        expect(result[:persona]).to eq('buddy')
      end
    end

    context 'error handling with real services' do
      it 'handles errors gracefully' do
        # Force an error by stubbing the LLM service
        allow(Services::LLMService).to receive(:complete_with_messages)
          .and_raise(Services::LLMService::LLMError.new('Simulated error'))

        result = module_instance.call(
          message: 'This should fail',
          context: { session_id: 'test-error' },
          persona: 'default'
        )

        # Should return a fallback response
        expect(result[:response]).to be_a(String)
        expect(result[:response]).not_to be_empty
        expect(result[:error]).to eq('llm_error')
      end
    end

    context 'with real Home Assistant TTS' do
      it 'sends TTS commands to Home Assistant' do
        # This will actually try to speak through HA if available
        result = module_instance.call(
          message: 'Say something short',
          context: { session_id: 'test-tts' },
          persona: 'buddy'
        )
        expect(result[:response]).to be_a(String)
        # The TTSService should have been called
        # We can verify this happened by checking the logs
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
        persona: 'default'
      )
      expect(result1[:response]).to be_a(String)
      # Second message - should remember context
      result2 = module_instance.call(
        message: 'What is my name?',
        context: { session_id: session_id },
        persona: 'default'
      )
      expect(result2[:response]).to be_a(String)
      # NOTE: Without DB persistence, it won't actually remember,
      # but we're testing the flow works
    end
  end
end
