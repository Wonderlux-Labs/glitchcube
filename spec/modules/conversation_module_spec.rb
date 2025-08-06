# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/modules/conversation_module'

RSpec.describe ConversationModule do
  let(:module_instance) { described_class.new }
  let(:mock_home_assistant) { instance_double(HomeAssistantClient) }
  let(:mock_llm_response) do
    double('LLMResponse',
      response_text: 'Mock AI response',
      continue_conversation?: true,
      cost: 0.001,
      model: 'test-model',
      usage: { prompt_tokens: 10, completion_tokens: 20 }
    )
  end

  before do
    # Mock the LLM service
    allow(Services::LLMService).to receive(:complete).and_return(mock_llm_response)
    
    # Mock HomeAssistantClient
    allow(HomeAssistantClient).to receive(:new).and_return(mock_home_assistant)
    allow(mock_home_assistant).to receive(:speak).and_return(true)
    
    # Mock the system prompt service
    mock_prompt_service = instance_double(Services::SystemPromptService)
    allow(Services::SystemPromptService).to receive(:new).and_return(mock_prompt_service)
    allow(mock_prompt_service).to receive(:generate).and_return('Test system prompt')
    
    # Mock the logger service
    allow(Services::LoggerService).to receive(:log_interaction)
    allow(Services::LoggerService).to receive(:log_tts)
  end

  describe '#call' do
    let(:message) { 'What is your name?' }
    let(:context) { { session_id: 'test-123' } }
    let(:mood) { 'neutral' }

    context 'when LLM service returns a response' do
      it 'returns the formatted response', :pending do
        result = module_instance.call(message: message, context: context, mood: mood)
        
        expect(result[:response]).to eq('Mock AI response')
        expect(result[:persona]).to eq('neutral')
        expect(result[:suggested_mood]).to eq('neutral')
        expect(result[:cost]).to eq(0.001)
        expect(result[:model]).to eq('test-model')
        expect(result[:continue_conversation]).to eq(true)
      end

      it 'speaks the response through Home Assistant', :pending do
        expect(mock_home_assistant).to receive(:speak)
          .with('Mock AI response')
        
        module_instance.call(message: message, context: context, mood: mood)
      end

      it 'logs the interaction', :pending do
        expect(Services::LoggerService).to receive(:log_interaction)
          .with(hash_including(
            user_message: message,
            ai_response: 'Mock AI response',
            mood: 'neutral'
          ))
        
        module_instance.call(message: message, context: context, mood: mood)
      end
    end

    context 'when LLM service fails' do
      before do
        allow(Services::LLMService).to receive(:complete)
          .and_raise(Services::LLMService::LLMError.new('API Error'))
      end

      it 'returns an offline fallback response', :pending do
        result = module_instance.call(message: message, context: context, mood: mood)
        
        # Should fall back to offline response
        expect(result[:response]).to include('offline')
        expect(result[:error]).to eq('llm_error')
      end

      it 'still speaks the fallback response', :pending do
        expect(mock_home_assistant).to receive(:speak)
          .with(a_string_including('offline'))
        
        module_instance.call(message: message, context: context, mood: mood)
      end
    end

    context 'when rate limited' do
      before do
        allow(Services::LLMService).to receive(:complete)
          .and_raise(Services::LLMService::RateLimitError.new('Rate limit exceeded'))
      end

      it 'returns a rate limit response', :pending do
        result = module_instance.call(message: message, context: context, mood: mood)
        
        expect(result[:response]).to include('pause')
        expect(result[:error]).to eq('rate_limit')
      end
    end

    context 'when general error occurs' do
      before do
        allow(Services::LLMService).to receive(:complete)
          .and_raise(StandardError.new('Network error'))
      end

      it 'returns a fallback response' do
        result = module_instance.call(message: message, context: context, mood: mood)
        
        expect(result[:response]).not_to be_nil
        expect(result[:error]).to eq('general_error')
        expect(result[:persona]).to eq('neutral')
      end
    end

    context 'with different personas' do
      %w[playful contemplative mysterious neutral].each do |persona|
        it "handles #{persona} persona correctly" do
          result = module_instance.call(message: message, context: context, mood: persona)
          
          expect(result[:persona]).to eq(persona)
          expect(result[:suggested_mood]).to eq(persona)
        end
      end
    end

    context 'with context parameters' do
      let(:enriched_context) do
        {
          session_id: 'test-session',
          source: 'api',
          interaction_count: 5
        }
      end

      it 'preserves context in the conversation' do
        result = module_instance.call(message: message, context: enriched_context, mood: mood)
        
        expect(result[:session_id]).to eq('test-session')
        expect(result[:conversation_id]).to eq('test-session')
      end
    end
  end
end