# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/conversation/conversation_session'

RSpec.describe ConversationModule do
  include_context 'with_full_conversation_setup'

  let(:message) { 'Hello, how are you today?' }
  let(:context) { { session_id: 'test-session' } }
  let(:flow_manager) { instance_double(Services::Conversation::ConversationFlowManager) }
  let(:feedback_service) { instance_double(Services::ConversationFeedbackService) }
  let(:side_effect_service) { instance_double(Services::ConversationSideEffectHandler) }

  # Mock response from flow manager
  let(:flow_response) do
    {
      response: 'Hello! I\'m doing great, thanks for asking!',
      conversation_id: 'conv-123',
      session_id: 'test-session',
      persona: 'buddy',
      model: 'gpt-3.5-turbo',
      cost: 0.001,
      tokens: { prompt_tokens: 10, completion_tokens: 15 },
      continue_conversation: true,
      tts_handled: false,
      voice_interaction: false,
      error: nil
    }
  end

  subject { ConversationModule.new }

  before do
    # Stub the flow manager dependency
    allow(Services::Conversation::ConversationFlowManager).to receive(:new).and_return(flow_manager)
    allow(flow_manager).to receive(:process_conversation).and_return(flow_response)

    # Stub feedback service
    allow(Services::ConversationFeedbackService).to receive(:new).and_return(feedback_service)
    allow(feedback_service).to receive(:set_state)

    # Stub side effect handler
    allow(Services::ConversationSideEffectHandler).to receive(:new).and_return(side_effect_service)
    allow(side_effect_service).to receive(:execute)

    # Stub simple logger
    allow(Services::Logging::SimpleLogger).to receive(:debug)
    allow(Services::Logging::SimpleLogger).to receive(:info)
    allow(Services::Logging::SimpleLogger).to receive(:log_error)
  end

  describe '#call' do
    context 'basic conversation processing' do
      it 'processes the message and returns the expected response structure' do
        result = subject.call(message: message, context: context)

        expect(result).to be_a_valid_conversation_response(expected_persona: 'buddy')
        expect(result[:response]).to eq('Hello! I\'m doing great, thanks for asking!')
        expect(result[:session_id]).to eq('test-session')
        expect(result[:conversation_id]).to eq('conv-123')
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

      it 'sets visual feedback states when feedback is enabled (default)' do
        subject.call(message: message, context: context)

        expect(feedback_service).to have_received(:set_state).with(:listening)
        expect(feedback_service).to have_received(:set_state).with(:thinking)
      end

      it 'skips visual feedback when explicitly disabled' do
        subject.call(message: message, context: context.merge(visual_feedback: false))

        expect(feedback_service).not_to have_received(:set_state)
      end

      it 'executes side effects after conversation processing' do
        subject.call(message: message, context: context)

        expect(side_effect_service).to have_received(:execute)
      end
    end

    context 'persona handling' do
      it 'uses the provided persona when specified' do
        subject.call(message: message, context: context, persona: 'jax')

        expect(flow_manager).to have_received(:process_conversation)
          .with(message: message, context: context, persona: 'jax')
      end

      it 'falls back to persona from context when no persona parameter provided' do
        subject.call(message: message, context: context.merge(persona: 'lomi'))

        expect(flow_manager).to have_received(:process_conversation)
          .with(message: message, context: hash_including(persona: 'lomi'), persona: nil)
      end

      it 'uses current persona service when no persona specified anywhere' do
        allow(Services::PersonaStateService).to receive(:get_current_persona).and_return('zorp')

        subject.call(message: message, context: context)

        expect(Services::Logging::SimpleLogger).to have_received(:debug)
          .with('Conversation started', hash_including(persona: 'zorp'))
      end
    end

    context 'error handling' do
      let(:error) { Services::Llm::LLMService::LLMError.new('Rate limit exceeded') }
      let(:error_response) do
        {
          response: 'I\'m having trouble processing your request right now. Please try again in a moment.',
          error: 'Rate limit exceeded',
          session_id: 'test-session',
          persona: 'buddy',
          continue_conversation: false
        }
      end

      before do
        allow(flow_manager).to receive(:process_conversation).and_raise(error)
        allow(Services::ConversationErrorHandler).to receive(:handle).and_return(error_response)
      end

      it 'handles LLM service errors gracefully' do
        result = subject.call(message: message, context: context)

        expect(result[:error]).to eq('Rate limit exceeded')
        expect(result[:response]).to include('trouble processing')
        expect(result[:continue_conversation]).to be false
      end

      it 'calls the error handler with correct parameters' do
        subject.call(message: message, context: context)

        expect(Services::ConversationErrorHandler).to have_received(:handle)
          .with(error, hash_including(session: nil, message: message, persona: 'buddy', context: context))
      end

      it 'logs errors appropriately' do
        subject.call(message: message, context: context)

        expect(Services::Logging::SimpleLogger).to have_received(:log_error)
          .with(hash_including(error: error, message: 'Conversation error occurred'))
      end

      it 'handles rate limit errors specifically' do
        rate_limit_error = Services::Llm::LLMService::RateLimitError.new('Rate limit exceeded')
        allow(flow_manager).to receive(:process_conversation).and_raise(rate_limit_error)

        result = subject.call(message: message, context: context)

        expect(result).to be_a(Hash)
        expect(result[:error]).to be_present
      end

      it 'handles standard errors' do
        standard_error = StandardError.new('Unexpected error')
        allow(flow_manager).to receive(:process_conversation).and_raise(standard_error)

        result = subject.call(message: message, context: context)

        expect(result).to be_a(Hash)
        expect(result[:error]).to be_present
      end
    end

    it_behaves_like 'handles conversation errors gracefully' do
      subject { ConversationModule.new.call(message: message, context: context) }
    end

    it_behaves_like 'provides visual feedback' do
      let(:conversation_context) { context }
      subject { ConversationModule.new.call(message: message, context: conversation_context) }
    end
  end

  describe 'class methods for persona switching' do
    before do
      allow(Services::PersonaStateService).to receive(:set_current_persona)
    end

    describe '.switch_persona' do
      it 'switches to the specified persona' do
        ConversationModule.switch_persona('jax')

        expect(Services::PersonaStateService).to have_received(:set_current_persona).with('jax')
      end
    end

    describe '.current_persona' do
      it 'returns the current active persona' do
        allow(Services::PersonaStateService).to receive(:get_current_persona).and_return('lomi')

        expect(ConversationModule.current_persona).to eq('lomi')
      end
    end

    describe 'persona convenience methods' do
      %w[buddy jax lomi zorp].each do |persona|
        describe ".#{persona}" do
          it "switches to #{persona} persona and returns a new instance" do
            instance = ConversationModule.send(persona)

            expect(Services::PersonaStateService).to have_received(:set_current_persona).with(persona)
            expect(instance).to be_a(ConversationModule)
          end
        end
      end
    end

    describe '.default' do
      it 'returns a new instance without switching persona' do
        instance = ConversationModule.default

        expect(Services::PersonaStateService).not_to have_received(:set_current_persona)
        expect(instance).to be_a(ConversationModule)
      end
    end
  end

  it_behaves_like 'supports persona switching' do
    subject { ConversationModule.new.call(message: message, context: context) }
  end
end
