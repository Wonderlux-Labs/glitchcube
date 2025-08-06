# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/modules/conversation_module'

RSpec.describe ConversationModule, :failing do
  let(:module_instance) { described_class.new }
  let(:mock_model) { instance_double('Desiru::Models::OpenRouter') }
  let(:mock_home_assistant) { instance_double(HomeAssistantClient) }

  before do
    # Mock the Desiru configuration
    allow(Desiru.configuration).to receive(:default_model).and_return(mock_model)
    allow(mock_model).to receive(:config).and_return({ model: 'openrouter/auto' })
    
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

    context 'when OpenRouter returns a properly formatted response' do
      let(:api_response) do
        {
          content: 'I am Glitch Cube, an autonomous art installation.',
          raw: { 'choices' => [{ 'message' => { 'content' => 'I am Glitch Cube' } }] },
          model: 'openrouter/auto',
          usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 }
        }
      end

      before do
        allow(Services::CircuitBreakerService).to receive_message_chain(:openrouter_breaker, :call)
          .and_yield
        allow(mock_model).to receive(:complete).and_return(api_response)
      end

      it 'returns the formatted response' do
        result = module_instance.call(message: message, context: context, mood: mood)
        
        expect(result[:response]).to eq('I am Glitch Cube, an autonomous art installation.')
        expect(result[:suggested_mood]).to eq('neutral')
        expect(result[:confidence]).to eq(0.95)
      end

      it 'speaks the response through Home Assistant' do
        expect(mock_home_assistant).to receive(:speak)
          .with('I am Glitch Cube, an autonomous art installation.')
        
        module_instance.call(message: message, context: context, mood: mood)
      end
    end

    context 'when OpenRouter returns a String response (edge case)' do
      before do
        allow(Services::CircuitBreakerService).to receive_message_chain(:openrouter_breaker, :call)
          .and_yield
        # Simulate the model returning a string instead of hash
        allow(mock_model).to receive(:complete).and_return('Plain text response')
      end

      it 'handles the string response gracefully with fallback' do
        result = module_instance.call(message: message, context: context, mood: mood)
        
        # Should fall back to a default response
        expect(result[:response]).to match(/interesting|perspective|thoughts/)
        expect(result[:confidence]).to eq(0.95)
      end
    end

    context 'when OpenRouter returns nil content' do
      let(:api_response) do
        {
          content: nil,
          raw: {},
          model: 'openrouter/auto',
          usage: { prompt_tokens: 10, completion_tokens: 0, total_tokens: 10 }
        }
      end

      before do
        allow(Services::CircuitBreakerService).to receive_message_chain(:openrouter_breaker, :call)
          .and_yield
        allow(mock_model).to receive(:complete).and_return(api_response)
      end

      it 'returns a fallback response' do
        result = module_instance.call(message: message, context: context, mood: mood)
        
        expect(result[:response]).not_to be_nil
        expect(result[:response]).to match(/interesting|perspective|thoughts/)
      end
    end

    context 'when circuit breaker is open' do
      before do
        allow(Services::CircuitBreakerService).to receive_message_chain(:openrouter_breaker, :call)
          .and_raise(CircuitBreaker::CircuitOpenError.new('Circuit open'))
      end

      it 'returns an offline response' do
        result = module_instance.call(message: message, context: context, mood: mood)
        
        expect(result[:response]).to include('offline')
        expect(result[:confidence]).to eq(0.3)
      end
    end

    context 'when request times out' do
      before do
        allow(Services::CircuitBreakerService).to receive_message_chain(:openrouter_breaker, :call)
          .and_yield
        allow(mock_model).to receive(:complete).and_raise(Timeout::Error.new('Request timeout'))
      end

      it 'returns an offline response' do
        result = module_instance.call(message: message, context: context, mood: mood)
        
        expect(result[:response]).to include('offline')
        expect(result[:confidence]).to eq(0.2)
      end
    end

    context 'when an unexpected error occurs' do
      before do
        allow(Services::CircuitBreakerService).to receive_message_chain(:openrouter_breaker, :call)
          .and_yield
        allow(mock_model).to receive(:complete).and_raise(StandardError.new("undefined method 'dig' for String"))
      end

      it 'returns a fallback response' do
        result = module_instance.call(message: message, context: context, mood: mood)
        
        expect(result[:response]).not_to be_nil
        expect(result[:confidence]).to eq(0.1)
      end

      it 'logs the error' do
        expect(Services::LoggerService).to receive(:log_interaction)
          .with(hash_including(
                  user_message: message,
                  mood: mood,
                  confidence: 0.1,
                  context: { error: "General Error: undefined method 'dig' for String" }
                ))
        
        module_instance.call(message: message, context: context, mood: mood)
      end
    end

    describe 'mood transitions' do
      it 'suggests playful mood when message contains play' do
        result = module_instance.call(message: "Let's play a game!", context: context, mood: 'neutral')
        expect(result[:suggested_mood]).to eq('playful')
      end

      it 'suggests contemplative mood when message contains think' do
        result = module_instance.call(message: "I've been thinking about art", context: context, mood: 'neutral')
        expect(result[:suggested_mood]).to eq('contemplative')
      end

      it 'suggests mysterious mood when message contains mystery' do
        result = module_instance.call(message: "That's quite mysterious", context: context, mood: 'neutral')
        expect(result[:suggested_mood]).to eq('mysterious')
      end
    end
  end
end