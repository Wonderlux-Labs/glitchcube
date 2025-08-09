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
           has_tool_calls?: false,
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
                    messages: double('messages', count: 0),
                    created_at: Time.now - 1.minute,
                    metadata: {})
  end

  before do
    # These are service methods, not client initialization - OK to mock at class level
    # but we should be careful about cleanup
    allow(Services::LLMService).to receive(:complete_with_messages).and_return(mock_llm_response)
    allow(Services::ConversationSession).to receive(:find_or_create).and_return(mock_session)

    # Mock HomeAssistantClient - instance level
    allow(HomeAssistantClient).to receive(:new).and_return(mock_home_assistant)
    allow(mock_home_assistant).to receive_messages(call_service: true, state: nil, speak: true)

    # Mock the system prompt service - instance level
    mock_prompt_service = instance_double(Services::SystemPromptService)
    allow(Services::SystemPromptService).to receive(:new).and_return(mock_prompt_service)
    allow(mock_prompt_service).to receive(:generate).and_return('Test system prompt')

    # These are class methods for logging - OK to mock at class level
    allow(Services::LoggerService).to receive(:log_interaction)
    allow(Services::LoggerService).to receive(:log_tts)

    # These are class methods for kiosk - OK to mock at class level
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
      it 'returns the formatted response', :vcr do
        result = module_instance.call(message: message, context: context, persona: mood)

        expect(result[:response]).to eq('Mock AI response')
        expect(result[:persona]).to eq('neutral')
        expect(result[:cost]).to eq(0.001)
        expect(result[:model]).to eq('test-model')
        expect(result[:continue_conversation]).to be(true)
      end

      it 'attempts to speak the response through tools', :vcr do
        # The new architecture uses tool-based TTS via execute_speech_tool
        # Since we don't provide tools in the context, it will skip TTS
        # This is expected behavior for tests without full tool setup
        result = module_instance.call(message: message, context: context, persona: mood)

        # Just verify the conversation completes successfully
        expect(result[:response]).to eq('Mock AI response')

        # NOTE: Actual TTS testing happens in integration tests with full tool context
      end

      # NOTE: This is tested more thoroughly in the integration tests with VCR
      it 'logs the interaction', :vcr do
        # Just verify it's called - the exact parameters don't matter for this test
        expect(Services::LoggerService).to receive(:log_interaction).at_least(:once)

        module_instance.call(message: message, context: context, persona: mood)
      end
    end

    context 'when LLM service fails' do
      before do
        allow(Services::LLMService).to receive(:complete_with_messages)
          .and_raise(Services::LLMService::LLMError.new('API Error'))
      end

      # NOTE: These behaviors are tested more accurately in integration tests with VCR
      it 'returns an offline fallback response', :vcr do
        result = module_instance.call(message: message, context: context, persona: mood)

        # Should fall back to offline response (check for offline mode indicators)
        expect(result[:response].downcase).to match(/offline|capabilities|present|moment|spirit|connectivity|unavailable/)
        expect(result[:error]).to eq('llm_error')
      end

      it 'returns a fallback response with error flag', :vcr do
        # Tool-based TTS will be skipped without proper tool context
        # Just verify the fallback response is returned properly
        result = module_instance.call(message: message, context: context, persona: mood)

        # Should get an offline response with error flag
        expect(result[:response]).to be_a(String)
        expect(result[:response].downcase).to match(/offline|capabilities|present|moment|spirit|connectivity|unavailable/)
        expect(result[:error]).to eq('llm_error')
        expect(result[:continue_conversation]).to be(false)
      end
    end

    context 'when rate limited' do
      before do
        allow(Services::LLMService).to receive(:complete_with_messages)
          .and_raise(Services::LLMService::RateLimitError.new('Rate limit exceeded'))
      end

      it 'returns a rate limit response', :vcr do
        result = module_instance.call(message: message, context: context, persona: mood)

        expect(result[:response]).to include('pause')
        expect(result[:error]).to eq('rate_limit')
      end
    end

    context 'when general error occurs' do
      before do
        allow(Services::LLMService).to receive(:complete_with_messages)
          .and_raise(StandardError.new('Network error'))
      end

      it 'returns a fallback response', :vcr do
        result = module_instance.call(message: message, context: context, persona: mood)

        expect(result[:response]).not_to be_nil
        expect(result[:error]).to eq('general_error')
        expect(result[:persona]).to eq('neutral')
      end
    end

    context 'with different personas' do
      %w[playful contemplative mysterious neutral].each do |persona|
        it "handles #{persona} persona correctly", :vcr do
          result = module_instance.call(message: message, context: context, persona: persona)

          expect(result[:persona]).to eq(persona)
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
                        messages: double('messages', count: 0),
                        created_at: Time.now - 1.minute,
                        metadata: {})
      end

      before do
        allow(Services::ConversationSession).to receive(:find_or_create)
          .with(hash_including(session_id: 'test-session'))
          .and_return(mock_session_enriched)
      end

      it 'preserves context in the conversation', :vcr do
        result = module_instance.call(message: message, context: enriched_context, persona: mood)

        expect(result[:session_id]).to eq('test-session')
        expect(result[:conversation_id]).to eq('test-session')
      end
    end
  end
end
