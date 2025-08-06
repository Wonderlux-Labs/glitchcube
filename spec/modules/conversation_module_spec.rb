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
           usage: { prompt_tokens: 10, completion_tokens: 20 })
  end
  let(:mock_conversation) do
    instance_double(Conversation,
                    session_id: 'test-123',
                    messages: double('messages', order: double(desc: double(limit: double(reverse: [])))),
                    add_message: double('message', role: 'assistant', content: 'response'),
                    update!: true,
                    total_cost: 0.0,
                    total_tokens: 0,
                    summary: { session_id: 'test-123' })
  end
  let(:mock_session) do
    instance_double(Services::ConversationSession,
                    session_id: 'test-123',
                    messages_for_llm: [],
                    add_message: true,
                    metadata: {})
  end

  before do
    # Mock the LLM service to use complete_with_messages
    allow(Services::LLMService).to receive(:complete_with_messages).and_return(mock_llm_response)

    # Mock ConversationSession to avoid database calls
    allow(Services::ConversationSession).to receive(:find_or_create).and_return(mock_session)

    # Mock HomeAssistantClient - TTSService calls call_service, not speak
    allow(HomeAssistantClient).to receive(:new).and_return(mock_home_assistant)
    allow(mock_home_assistant).to receive(:call_service).and_return(true)

    # Mock the system prompt service
    mock_prompt_service = instance_double(Services::SystemPromptService)
    allow(Services::SystemPromptService).to receive(:new).and_return(mock_prompt_service)
    allow(mock_prompt_service).to receive(:generate).and_return('Test system prompt')

    # Mock the logger service
    allow(Services::LoggerService).to receive(:log_interaction)
    allow(Services::LoggerService).to receive(:log_tts)

    # Mock KioskService
    allow(Services::KioskService).to receive(:update_mood)
    allow(Services::KioskService).to receive(:update_interaction)
    allow(Services::KioskService).to receive(:add_inner_thought)

    # Mock AWTRIX display methods
    allow(mock_home_assistant).to receive(:awtrix_display_text)
    allow(mock_home_assistant).to receive(:awtrix_mood_light)
  end

  describe '#call' do
    let(:message) { 'What is your name?' }
    let(:context) { { session_id: 'test-123' } }
    let(:mood) { 'neutral' }

    context 'when LLM service returns a response' do
      it 'returns the formatted response' do
        result = module_instance.call(message: message, context: context, mood: mood)

        expect(result[:response]).to eq('Mock AI response')
        expect(result[:persona]).to eq('neutral')
        expect(result[:suggested_mood]).to eq('neutral')
        expect(result[:cost]).to eq(0.001)
        expect(result[:model]).to eq('test-model')
        expect(result[:continue_conversation]).to be(true)
      end

      it 'speaks the response through Home Assistant' do
        expect(mock_home_assistant).to receive(:call_service)
          .with('script', 'glitchcube_tts', hash_including(message: 'Mock AI response'))

        module_instance.call(message: message, context: context, mood: mood)
      end

      # NOTE: This is tested more thoroughly in the integration tests with VCR
      xit 'logs the interaction' do
        # Just verify it's called - the exact parameters don't matter for this test
        expect(Services::LoggerService).to receive(:log_interaction).at_least(:once)

        module_instance.call(message: message, context: context, mood: mood)
      end
    end

    context 'when LLM service fails' do
      before do
        allow(Services::LLMService).to receive(:complete_with_messages)
          .and_raise(Services::LLMService::LLMError.new('API Error'))
      end

      # NOTE: These behaviors are tested more accurately in integration tests with VCR
      xit 'returns an offline fallback response' do
        result = module_instance.call(message: message, context: context, mood: mood)

        # Should fall back to offline response (check for offline mode indicators)
        expect(result[:response].downcase).to match(/offline|can't access|capabilities/)
        expect(result[:error]).to eq('llm_error')
      end

      xit 'still speaks the fallback response' do
        expect(mock_home_assistant).to receive(:call_service)
          .with('script', 'glitchcube_tts', hash_including(message: a_string_including('offline')))

        module_instance.call(message: message, context: context, mood: mood)
      end
    end

    context 'when rate limited' do
      before do
        allow(Services::LLMService).to receive(:complete_with_messages)
          .and_raise(Services::LLMService::RateLimitError.new('Rate limit exceeded'))
      end

      it 'returns a rate limit response' do
        result = module_instance.call(message: message, context: context, mood: mood)

        expect(result[:response]).to include('pause')
        expect(result[:error]).to eq('rate_limit')
      end
    end

    context 'when general error occurs' do
      before do
        allow(Services::LLMService).to receive(:complete_with_messages)
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

      let(:mock_session_enriched) do
        instance_double(Services::ConversationSession,
                        session_id: 'test-session',
                        messages_for_llm: [],
                        add_message: true,
                        metadata: {})
      end

      before do
        allow(Services::ConversationSession).to receive(:find_or_create)
          .with(hash_including(session_id: 'test-session'))
          .and_return(mock_session_enriched)
      end

      it 'preserves context in the conversation' do
        result = module_instance.call(message: message, context: enriched_context, mood: mood)

        expect(result[:session_id]).to eq('test-session')
        expect(result[:conversation_id]).to eq('test-session')
      end
    end
  end
end
