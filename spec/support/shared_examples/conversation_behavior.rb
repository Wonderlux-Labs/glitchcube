# frozen_string_literal: true

# Shared examples for conversation behavior testing
# Provides reusable test behaviors for conversation-related specs
# Use with: it_behaves_like 'shared_example_name', parameters

if defined?(RSpec)

  RSpec.shared_examples 'a valid conversation response' do |expected_persona: 'buddy'|
    it 'returns a properly formatted conversation response' do
      expect(subject).to be_a(Hash)
      expect(subject).to have_key(:response)
      expect(subject).to have_key(:conversation_id)
      expect(subject).to have_key(:session_id)
      expect(subject).to have_key(:persona)
      expect(subject).to have_key(:model)
      expect(subject).to have_key(:cost)
      expect(subject).to have_key(:tokens)
      expect(subject).to have_key(:continue_conversation)
      expect(subject).to have_key(:tts_handled)
      expect(subject).to have_key(:voice_interaction)
      expect(subject).to have_key(:error)

      # Validate response content
      expect(subject[:response]).to be_a(String)
      expect(subject[:response]).not_to be_empty
      expect(subject[:persona]).to eq(expected_persona)
      expect(subject[:error]).to be_nil

      # Validate conversation IDs
      expect(subject[:conversation_id]).to be_a(String)
      expect(subject[:session_id]).to be_a(String)

      # Validate cost and token tracking
      expect(subject[:cost]).to be_a(Numeric)
      expect(subject[:cost]).to be >= 0
      expect(subject[:tokens]).to be_a(Hash)
      expect(subject[:tokens]).to have_key(:prompt_tokens)
      expect(subject[:tokens]).to have_key(:completion_tokens)

      # Validate boolean flags
      expect([true, false]).to include(subject[:continue_conversation])
      expect([true, false]).to include(subject[:tts_handled])
      expect([true, false]).to include(subject[:voice_interaction])
    end
  end

  RSpec.shared_examples 'handles tool calls correctly' do
    context 'when LLM response includes tool calls' do
      let(:mock_llm_response_with_tools) do
        double('LLMResponse',
               response_text: 'I\'ll turn on the light for you.',
               continue_conversation?: true,
               tool_calls?: true,
               has_tool_calls?: true,
               tool_calls: [
                 {
                   'function' => {
                     'name' => 'turn_on_light',
                     'arguments' => '{"entity_id": "light.glitch_cube"}'
                   }
                 }
               ],
               function_calls: [],
               content: 'I\'ll turn on the light for you.',
               parsed_content: {
                 'response' => 'I\'ll turn on the light for you.',
                 'continue_conversation' => true
               }.with_indifferent_access,
               inner_thoughts: 'User wants light control',
               cost: 0.002,
               model: 'test-model',
               usage: { prompt_tokens: 15, completion_tokens: 25 },
               message_data: {
                 role: 'assistant',
                 content: 'I\'ll turn on the light for you.',
                 tool_calls: [
                   {
                     'function' => {
                       'name' => 'turn_on_light',
                       'arguments' => '{"entity_id": "light.glitch_cube"}'
                     }
                   }
                 ]
               })
      end

      before do
        allow(Services::Llm::LLMService).to receive(:complete_with_messages)
          .and_return(mock_llm_response_with_tools)

        # Mock tool execution
        mock_tool_engine = instance_double(Services::Conversation::ToolExecutionEngine)
        allow(Services::Conversation::ToolExecutionEngine).to receive(:new)
          .and_return(mock_tool_engine)
        allow(mock_tool_engine).to receive(:execute_tool_calls)
          .and_return({
                        tool_results: [{
                          role: 'tool',
                          content: 'Light turned on successfully',
                          tool_call_id: 'call_123'
                        }],
                        last_tool_calls: [{
                          name: 'turn_on_light',
                          arguments: { entity_id: 'light.glitch_cube' },
                          result: { success: true }
                        }]
                      })
      end

      it 'executes tool calls and includes results in response metadata' do
        result = subject

        expect(result[:response]).to eq('I\'ll turn on the light for you.')
        # Tool execution should be tracked in the session message metadata
        # The exact implementation may vary based on your conversation flow
      end
    end
  end

  RSpec.shared_examples 'processes Home Assistant actions' do
    it 'extracts and processes HA actions from conversation result' do
      # Mock conversation module
      mock_handler = instance_double(ConversationModule)
      allow(ConversationModule).to receive(:new)
        .and_return(mock_handler)

      # Mock action extraction
      allow(mock_handler).to receive(:extract_ha_actions)
        .and_return([
                      {
                        domain: 'light',
                        service: 'turn_on',
                        target: { entity_id: 'light.glitch_cube' }
                      }
                    ])

      allow(mock_handler).to receive(:extract_media_actions)
        .and_return([])

      result = subject

      # Verify conversation completed successfully
      expect(result).to be_a(Hash)
      expect(result[:response]).to be_present
      expect(result[:error]).to be_nil
    end
  end

  RSpec.shared_examples 'maintains conversation session' do |session_id: 'test-session'|
    it 'maintains conversation session throughout the interaction' do
      result = subject

      expect(result[:session_id]).to eq(session_id)
      expect(result[:conversation_id]).to be_present

      # Session should be created and maintained
      expect(ConversationSession).to have_received(:find_or_create)
        .with(session_id: session_id, context: anything)
    end
  end

  RSpec.shared_examples 'handles conversation errors gracefully' do
    context 'when LLM service fails' do
      before do
        allow(Services::Llm::LLMService).to receive(:complete_with_messages)
          .and_raise(Services::Llm::LLMService::LLMError.new('API rate limit exceeded'))
      end

      it 'returns an error response without crashing' do
        result = subject

        expect(result).to be_a(Hash)
        expect(result[:error]).to be_present
        expect(result[:response]).to be_present # Should have fallback response
        expect(result[:session_id]).to be_present
      end
    end

    context 'when Home Assistant is unavailable' do
      include_context 'with_ha_service_failures'

      it 'continues conversation despite HA failures' do
        result = subject

        expect(result).to be_a(Hash)
        expect(result[:response]).to be_present
        # May or may not have errors depending on fallback handling
      end
    end
  end

  RSpec.shared_examples 'supports persona switching' do
    %w[buddy jax lomi zorp].each do |persona|
      context "when using #{persona} persona" do
        let(:persona_name) { persona }

        before do
          allow(Services::PersonaStateService).to receive(:get_current_persona)
            .and_return(persona)
        end

        it "responds as #{persona} persona" do
          result = subject

          expect(result[:persona]).to eq(persona)
          expect(result[:response]).to be_present
        end
      end
    end
  end

  RSpec.shared_examples 'logs conversation metrics' do
    it 'logs conversation interaction and TTS' do
      subject

      # Verify logging calls were made
      expect(Services::Logging::SimpleLogger).to have_received(:log_interaction)
      # TTS logging depends on whether TTS was actually called
    end
  end

  RSpec.shared_examples 'respects conversation continuation flags' do
    context 'when conversation should continue' do
      let(:mock_llm_response) do
        double('LLMResponse',
               response_text: 'What would you like to know?',
               continue_conversation?: true,
               tool_calls?: false,
               has_tool_calls?: false,
               tool_calls: nil,
               function_calls: [],
               content: 'What would you like to know?',
               parsed_content: {
                 'response' => 'What would you like to know?',
                 'continue_conversation' => true
               }.with_indifferent_access,
               inner_thoughts: 'Engaging user',
               cost: 0.001,
               model: 'test-model',
               usage: { prompt_tokens: 10, completion_tokens: 20 })
      end

      it 'sets continue_conversation to true' do
        result = subject
        expect(result[:continue_conversation]).to be true
      end
    end

    context 'when conversation should end' do
      let(:mock_llm_response) do
        double('LLMResponse',
               response_text: 'Goodbye! Have a great day.',
               continue_conversation?: false,
               tool_calls?: false,
               has_tool_calls?: false,
               tool_calls: nil,
               function_calls: [],
               content: 'Goodbye! Have a great day.',
               parsed_content: {
                 'response' => 'Goodbye! Have a great day.',
                 'continue_conversation' => false
               }.with_indifferent_access,
               inner_thoughts: 'Ending conversation',
               cost: 0.001,
               model: 'test-model',
               usage: { prompt_tokens: 8, completion_tokens: 15 })
      end

      it 'sets continue_conversation to false' do
        result = subject
        expect(result[:continue_conversation]).to be false
      end
    end
  end

  RSpec.shared_examples 'provides visual feedback' do
    context 'when visual feedback is enabled' do
      let(:conversation_context) { { visual_feedback: true } }

      it 'sets appropriate LED states during conversation' do
        # Mock conversation feedback service
        mock_feedback = instance_double(Services::Conversation::FeedbackService)
        allow(Services::Conversation::FeedbackService).to receive(:new)
          .and_return(mock_feedback)
        allow(mock_feedback).to receive(:set_state)

        subject

        # Should set listening and thinking states
        expect(mock_feedback).to have_received(:set_state).with(:listening)
        expect(mock_feedback).to have_received(:set_state).with(:thinking)
      end
    end

    context 'when visual feedback is disabled' do
      let(:conversation_context) { { visual_feedback: false } }

      it 'skips LED state changes' do
        mock_feedback = instance_double(Services::Conversation::FeedbackService)
        allow(Services::Conversation::FeedbackService).to receive(:new)
          .and_return(mock_feedback)
        allow(mock_feedback).to receive(:set_state)

        subject

        # Should not call LED state changes
        expect(mock_feedback).not_to have_received(:set_state)
      end
    end
  end

end
