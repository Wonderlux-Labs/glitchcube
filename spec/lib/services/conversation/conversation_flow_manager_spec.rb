# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::Conversation::ConversationFlowManager do
  include_context 'with_full_conversation_setup'

  subject { described_class.new }

  let(:message) { 'Hello there!' }
  let(:context) { { session_id: 'test-session' } }
  let(:persona) { 'buddy' }

  describe '#process_conversation' do
    context 'with successful LLM interaction' do
      it 'returns a complete conversation response' do
        result = subject.process_conversation(message: message, context: context, persona: persona)

        expect(result).to be_a_valid_conversation_response(expected_persona: 'buddy')
        expect(result[:response]).to be_a(String)
        expect(result[:response]).not_to be_empty
        expect(result[:session_id]).to eq('test-session')
        expect(result[:continue_conversation]).to be(true)
      end

      it 'handles message processing end-to-end' do
        result = subject.process_conversation(message: message, context: context, persona: persona)

        # Verify the core conversation structure
        expect(result).to include(
          :response,
          :conversation_id,
          :session_id,
          :persona,
          :model,
          :cost,
          :tokens,
          :continue_conversation,
          :tts_handled,
          :voice_interaction,
          :error
        )
      end

      it 'preserves context session information' do
        enriched_context = context.merge(voice_interaction: true, visual_feedback: false)

        result = subject.process_conversation(message: message, context: enriched_context, persona: persona)

        expect(result[:session_id]).to eq('test-session')
        expect(result[:voice_interaction]).to be(true)
      end

      it 'defaults to current persona when none specified' do
        allow(Services::PersonaStateService).to receive(:get_current_persona).and_return('jax')

        result = subject.process_conversation(message: message, context: context)

        expect(result[:persona]).to eq('jax')
      end
    end

    context 'with different personas' do
      %w[buddy jax lomi zorp].each do |persona_name|
        it "processes conversation correctly with #{persona_name} persona" do
          result = subject.process_conversation(message: message, context: context, persona: persona_name)

          expect(result).to be_a_valid_conversation_response(expected_persona: persona_name)
          expect(result[:persona]).to eq(persona_name)
        end
      end
    end

    context 'with tool usage scenarios' do
      let(:tool_context) { context.merge(tools: [{ type: 'function', function: { name: 'test_tool' } }]) }

      it 'handles conversations with tools available' do
        result = subject.process_conversation(message: 'Turn on the lights', context: tool_context, persona: persona)

        expect(result).to be_a_valid_conversation_response
        expect(result[:session_id]).to eq('test-session')
      end
    end

    context 'error scenarios' do
      before do
        # Mock LLM service to fail
        allow(Services::Llm::LLMService).to receive(:complete_with_messages)
          .and_raise(Services::Llm::LLMService::LLMError.new('LLM service unavailable'))

        # Mock error handler response
        allow(Services::ConversationErrorHandler).to receive(:handle).and_return({
                                                                                   response: 'I\'m currently having some technical difficulties.',
                                                                                   conversation_id: 'error-conv',
                                                                                   session_id: 'test-session',
                                                                                   persona: 'buddy',
                                                                                   model: nil,
                                                                                   cost: 0.0,
                                                                                   tokens: { prompt_tokens: 0, completion_tokens: 0 },
                                                                                   continue_conversation: false,
                                                                                   tts_handled: false,
                                                                                   voice_interaction: false,
                                                                                   error: 'llm_error'
                                                                                 })
      end

      it 'handles LLM service failures gracefully' do
        result = subject.process_conversation(message: message, context: context, persona: persona)

        expect(result[:error]).to eq('llm_error')
        expect(result[:response]).to include('technical difficulties')
        expect(result[:continue_conversation]).to be(false)
        expect(Services::ConversationErrorHandler).to have_received(:handle)
      end

      it 'preserves session information during errors' do
        result = subject.process_conversation(message: message, context: context, persona: persona)

        expect(result[:session_id]).to eq('test-session')
        expect(result[:persona]).to eq('buddy')
      end
    end

    context 'rate limiting scenarios' do
      before do
        allow(Services::Llm::LLMService).to receive(:complete_with_messages)
          .and_raise(Services::Llm::LLMService::RateLimitError.new('Rate limit exceeded'))

        allow(Services::ConversationErrorHandler).to receive(:handle).and_return({
                                                                                   response: 'I need to take a quick pause. Please try again in a moment.',
                                                                                   conversation_id: 'rate-limit-conv',
                                                                                   session_id: 'test-session',
                                                                                   persona: 'buddy',
                                                                                   model: nil,
                                                                                   cost: 0.0,
                                                                                   tokens: { prompt_tokens: 0, completion_tokens: 0 },
                                                                                   continue_conversation: false,
                                                                                   tts_handled: false,
                                                                                   voice_interaction: false,
                                                                                   error: 'rate_limit'
                                                                                 })
      end

      it 'handles rate limiting appropriately' do
        result = subject.process_conversation(message: message, context: context, persona: persona)

        expect(result[:error]).to eq('rate_limit')
        expect(result[:response]).to include('pause')
        expect(result[:continue_conversation]).to be(false)
      end
    end

    context 'with various context configurations' do
      it 'handles empty context gracefully' do
        result = subject.process_conversation(message: message, context: {}, persona: persona)

        expect(result).to be_a_valid_conversation_response
        expect(result[:session_id]).to be_a(String)
        expect(result[:session_id]).not_to be_empty
      end

      it 'handles context with custom session ID' do
        custom_context = { session_id: 'custom-session-id' }

        result = subject.process_conversation(message: message, context: custom_context, persona: persona)

        expect(result[:session_id]).to eq('custom-session-id')
      end

      it 'handles context with additional metadata' do
        metadata_context = context.merge(
          source: 'api',
          interaction_count: 5,
          user_preferences: { voice_enabled: true }
        )

        result = subject.process_conversation(message: message, context: metadata_context, persona: persona)

        expect(result).to be_a_valid_conversation_response
        expect(result[:session_id]).to eq('test-session')
      end
    end

    context 'conversation continuation behavior' do
      it 'properly handles conversation continuation flags' do
        result = subject.process_conversation(message: message, context: context, persona: persona)

        expect(result[:continue_conversation]).to be_in([true, false])
      end

      it 'tracks conversation metrics' do
        result = subject.process_conversation(message: message, context: context, persona: persona)

        expect(result[:cost]).to be_a(Numeric)
        expect(result[:cost]).to be >= 0
        expect(result[:tokens]).to be_a(Hash)
        expect(result[:tokens]).to include(:prompt_tokens, :completion_tokens)
      end
    end
  end

  describe 'integration with conversation components' do
    it 'coordinates between all conversation services' do
      # This tests the orchestration through public interface
      result = subject.process_conversation(message: message, context: context, persona: persona)

      # Verify proper coordination resulted in valid output
      expect(result).to be_a_valid_conversation_response

      # Verify logging occurred (indicating service coordination)
      expect(Services::Logging::SimpleLogger).to have_received(:debug).at_least(:once)
      expect(Services::Logging::SimpleLogger).to have_received(:info).at_least(:once)
    end

    it 'handles complex conversation flows' do
      complex_message = 'Hey there! Can you tell me what time it is and also turn on the living room lights?'

      result = subject.process_conversation(message: complex_message, context: context, persona: persona)

      expect(result).to be_a_valid_conversation_response
      expect(result[:response]).to be_a(String)
      expect(result[:response]).not_to be_empty
    end
  end
end
