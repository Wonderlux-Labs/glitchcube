# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConversationModule do
  include_context 'with_full_conversation_setup'

  let(:message) { 'What is your name?' }
  let(:context) { { session_id: 'test-session' } }
  let(:flow_manager) { instance_double(Services::Conversation::FlowManager) }

  subject { described_class.new }

  before do
    # Mock the core dependencies with minimal setup
    allow(Services::Conversation::FlowManager).to receive(:new).and_return(flow_manager)
  end

  describe '#call' do
    let(:successful_response) do
      {
        response: 'Hello! I am Buddy, your friendly conversation companion.',
        conversation_id: 'conv-123',
        session_id: 'test-session',
        persona: 'buddy',
        model: 'gpt-3.5-turbo',
        cost: 0.001,
        tokens: { prompt_tokens: 10, completion_tokens: 25 },
        continue_conversation: true,
        tts_handled: false,
        voice_interaction: false,
        error: nil
      }
    end

    context 'when conversation flows normally' do
      before do
        allow(flow_manager).to receive(:process_conversation).and_return(successful_response)
      end

      it 'returns a valid conversation response' do
        result = subject.call(message: message, context: context)

        expect(result).to be_a_valid_conversation_response
        expect(result[:response]).to eq('Hello! I am Buddy, your friendly conversation companion.')
        expect(result[:session_id]).to eq('test-session')
        expect(result[:persona]).to eq('buddy')
        expect(result[:error]).to be_nil
      end

      it 'delegates to flow manager with correct parameters' do
        subject.call(message: message, context: context)

        expect(flow_manager).to have_received(:process_conversation)
          .with(message: message, context: context, persona: nil)
      end

      it 'logs conversation start and completion' do
        subject.call(message: message, context: context)

        expect(Services::Logging::SimpleLogger).to have_received(:debug)
          .with('Conversation started', hash_including(tagged: [:conversation], persona: 'buddy'))
        expect(Services::Logging::SimpleLogger).to have_received(:info)
          .with('Conversation completed', hash_including(tagged: [:conversation]))
      end

      it 'logs conversation start and completion' do
        expect(Services::Logging::SimpleLogger).to receive(:debug).with('Conversation started', any_args)
        expect(Services::Logging::SimpleLogger).to receive(:info).with('Conversation completed', any_args)

        subject.call(message: message, context: context)
      end
    end

    context 'when LLM service fails' do
      let(:error_response) do
        {
          response: 'I\'m currently offline, but my spirit is still present. How can I help you with my current capabilities?',
          conversation_id: 'conv-error',
          session_id: 'test-session',
          persona: 'buddy',
          model: nil,
          cost: 0.0,
          tokens: { prompt_tokens: 0, completion_tokens: 0 },
          continue_conversation: false,
          tts_handled: false,
          voice_interaction: false,
          error: 'llm_error'
        }
      end

      before do
        allow(flow_manager).to receive(:process_conversation).and_return(error_response)
      end

      it 'returns an offline fallback response' do
        result = subject.call(message: message, context: context)

        expect(result[:response]).to include('offline')
        expect(result[:error]).to eq('llm_error')
        expect(result[:continue_conversation]).to be(false)
      end

      it 'still provides a helpful response structure' do
        result = subject.call(message: message, context: context)

        expect(result).to be_a_valid_conversation_response(expected_error: 'llm_error')
        expect(result[:response]).to be_a(String)
        expect(result[:response]).not_to be_empty
      end
    end

    context 'when rate limited' do
      let(:rate_limit_response) do
        {
          response: 'I need to take a quick pause to catch my digital breath. Try again in just a moment!',
          conversation_id: 'conv-rate-limit',
          session_id: 'test-session',
          persona: 'buddy',
          model: nil,
          cost: 0.0,
          tokens: { prompt_tokens: 0, completion_tokens: 0 },
          continue_conversation: false,
          tts_handled: false,
          voice_interaction: false,
          error: 'rate_limit'
        }
      end

      before do
        allow(flow_manager).to receive(:process_conversation).and_return(rate_limit_response)
      end

      it 'returns a rate limit response' do
        result = subject.call(message: message, context: context)

        expect(result[:response]).to include('pause')
        expect(result[:error]).to eq('rate_limit')
        expect(result[:continue_conversation]).to be(false)
      end
    end

    context 'when general error occurs' do
      let(:general_error_response) do
        {
          response: 'Hmm, something went wonky there. Could you try asking that again?',
          conversation_id: 'conv-general-error',
          session_id: 'test-session',
          persona: 'buddy',
          model: nil,
          cost: 0.0,
          tokens: { prompt_tokens: 0, completion_tokens: 0 },
          continue_conversation: false,
          tts_handled: false,
          voice_interaction: false,
          error: 'general_error'
        }
      end

      before do
        allow(flow_manager).to receive(:process_conversation).and_return(general_error_response)
      end

      it 'returns a fallback response' do
        result = subject.call(message: message, context: context)

        expect(result[:response]).not_to be_nil
        expect(result[:error]).to eq('general_error')
        expect(result[:continue_conversation]).to be(false)
      end
    end

    context 'with different personas' do
      %w[buddy jax lomi zorp].each do |persona|
        it "handles #{persona} persona correctly" do
          persona_response = successful_response.merge(persona: persona)
          allow(flow_manager).to receive(:process_conversation).and_return(persona_response)

          result = subject.call(message: message, context: context, persona: persona)

          expect(result[:persona]).to eq(persona)
          expect(result).to be_a_valid_conversation_response(expected_persona: persona)
        end
      end

      it 'defaults to buddy persona when not specified' do
        allow(flow_manager).to receive(:process_conversation).and_return(successful_response)

        result = subject.call(message: message, context: context)
        expect(result[:persona]).to eq('buddy')
      end

      it 'uses the correct persona for responses' do
        allow(flow_manager).to receive(:process_conversation).and_return(successful_response)

        result = subject.call(message: message, context: context, persona: 'buddy')

        expect(result[:persona]).to eq('buddy')
        expect(result[:response]).to be_a(String)
        expect(result[:response]).not_to be_empty
      end
    end

    context 'with enriched context parameters' do
      let(:enriched_context) do
        {
          session_id: 'test-session-enriched',
          source: 'api',
          interaction_count: 5,
          visual_feedback: true,
          voice_interaction: true
        }
      end

      let(:enriched_response) do
        successful_response.merge(
          session_id: 'test-session-enriched',
          conversation_id: 'conv-enriched',
          voice_interaction: true
        )
      end

      before do
        allow(flow_manager).to receive(:process_conversation).and_return(enriched_response)
      end

      it 'preserves context in the conversation' do
        result = subject.call(message: message, context: enriched_context)

        expect(result[:session_id]).to eq('test-session-enriched')
        expect(result[:conversation_id]).to eq('conv-enriched')
        expect(result[:voice_interaction]).to be(true)
      end

      it 'passes enriched context to flow manager' do
        subject.call(message: message, context: enriched_context)

        expect(flow_manager).to have_received(:process_conversation)
          .with(message: message, context: enriched_context, persona: nil)
      end
    end

    context 'error handling and logging' do
      let(:error_response) do
        {
          response: 'Hmm, something went wonky there. Could you try asking that again?',
          conversation_id: 'conv-error',
          session_id: 'test-session',
          persona: 'buddy',
          model: nil,
          cost: 0.0,
          tokens: { prompt_tokens: 0, completion_tokens: 0 },
          continue_conversation: false,
          tts_handled: false,
          voice_interaction: false,
          error: 'general_error'
        }
      end

      before do
        # Mock the error handler to return a proper error response
        allow(Services::Conversation::ErrorHandler).to receive(:handle).and_return(error_response)
      end

      it 'handles flow manager failures gracefully' do
        allow(flow_manager).to receive(:process_conversation).and_raise(StandardError.new('Flow manager error'))

        result = subject.call(message: message, context: context)

        # Should get error response from error handler
        expect(result).to eq(error_response)
        expect(Services::Conversation::ErrorHandler).to have_received(:handle)
      end
    end
  end
end
