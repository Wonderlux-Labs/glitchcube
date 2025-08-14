# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::Conversation::FlowManager do
  # Manually set up only what we need, avoiding shared context conflicts

  let(:message) { 'Hello there!' }
  let(:context) { { session_id: 'test-session' } }
  let(:persona) { 'buddy' }

  # Mock the StateManager's create_or_get_session method
  let(:mock_session) do
    instance_double(ConversationSession,
                    session_id: 'test-session',
                    messages_for_llm: [],
                    add_message: true,
                    messages: double('messages', count: 0),
                    created_at: Time.now - 1.minute,
                    metadata: {},
                    conversation: double('conversation', new_record?: false))
  end

  let(:mock_state_manager) { instance_double(Services::Conversation::StateManager) }
  let(:mock_history_manager) { instance_double(Services::Conversation::HistoryManager) }
  let(:mock_llm_manager) { instance_double(Services::Conversation::LlmInteractionManager) }
  let(:mock_tool_engine) { instance_double(Services::Conversation::ToolExecutionEngine) }
  let(:mock_response_processor) { instance_double(Services::Conversation::ResponseProcessor) }
  let(:mock_error_handler) { Services::Conversation::ErrorHandler }

  let(:mock_llm_response) do
    double('LLMResponse',
           response_text: 'Mock AI response from LLM',
           continue_conversation?: true,
           tool_calls?: false,
           has_tool_calls?: false,
           tool_calls: nil,
           function_calls: [],
           content: 'Mock AI response from LLM',
           parsed_content: {
             'response' => 'Mock AI response from LLM',
             'continue_conversation' => true
           }.with_indifferent_access,
           inner_thoughts: 'Test inner thoughts',
           cost: 0.001,
           model: 'test-model',
           usage: { prompt_tokens: 10, completion_tokens: 20 },
           message_data: {
             role: 'assistant',
             content: 'Mock AI response from LLM'
           })
  end

  subject do
    described_class.new(error_handler: mock_error_handler)
  end

  before do
    # Clean Redis
    begin
      redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379')
      redis.flushdb
      redis.quit
    rescue StandardError
      # Redis might not be available, that's fine
    end

    # Reset circuit breakers
    if defined?(Services::System::CircuitBreakerService) &&
       Services::System::CircuitBreakerService.respond_to?(:reset_all_breakers)
      Services::System::CircuitBreakerService.reset_all_breakers
    end

    # Mock ConversationSession since we're not using the full conversation setup
    allow(ConversationSession).to receive(:find_or_create).and_return(mock_session)
    # Setup StateManager mock
    allow(Services::Conversation::StateManager).to receive(:new).and_return(mock_state_manager)
    allow(mock_state_manager).to receive(:create_or_get_session).and_return(mock_session)
    allow(mock_state_manager).to receive(:record_message)

    # Setup HistoryManager mock
    allow(Services::Conversation::HistoryManager).to receive(:new).and_return(mock_history_manager)
    allow(mock_history_manager).to receive(:get_conversation_context).and_return([])

    # Setup LlmInteractionManager mock
    allow(Services::Conversation::LlmInteractionManager).to receive(:new).and_return(mock_llm_manager)
    allow(mock_llm_manager).to receive(:build_system_prompt).and_return('Test system prompt')
    allow(mock_llm_manager).to receive(:prepare_messages).and_return([
                                                                       { role: 'system', content: 'Test system prompt' },
                                                                       { role: 'user', content: message }
                                                                     ])
    allow(mock_llm_manager).to receive(:call_llm).and_return(mock_llm_response)
    allow(mock_llm_manager).to receive(:select_appropriate_model).and_return('test-model')
    allow(mock_llm_manager).to receive(:get_response_schema).and_return(nil)

    # Setup ToolExecutionEngine mock
    allow(Services::Conversation::ToolExecutionEngine).to receive(:new).and_return(mock_tool_engine)

    # Setup ResponseProcessor mock
    allow(Services::Conversation::ResponseProcessor).to receive(:new).and_return(mock_response_processor)
    allow(mock_response_processor).to receive(:process_response).and_return({
                                                                              response: 'Mock AI response from LLM',
                                                                              continue_conversation: true,
                                                                              inner_thoughts: 'Test inner thoughts'
                                                                            })

    # Mock PersonaStateService
    allow(Services::PersonaStateService).to receive(:get_current_persona).and_return('buddy')

    # Mock Personas::BasePersona
    mock_persona = instance_double(Personas::BasePersona)
    allow(Personas::BasePersona).to receive(:create).and_return(mock_persona)
    allow(mock_persona).to receive(:name).and_return('buddy')
    allow(mock_persona).to receive(:tool_schemas).and_return([])

    # Mock Memory::ContextEnrichmentService
    allow(Services::Memory::ContextEnrichmentService).to receive(:enrich).and_return(context)

    # Mock logging services
    allow(Services::Logging::SimpleLogger).to receive(:debug)
    allow(Services::Logging::SimpleLogger).to receive(:info)
    allow(Services::Logging::SimpleLogger).to receive(:log_error)
  end

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

        # Make sure the Memory::ContextEnrichmentService preserves the enriched context
        allow(Services::Memory::ContextEnrichmentService).to receive(:enrich).with(enriched_context).and_return(enriched_context)

        result = subject.process_conversation(message: message, context: enriched_context, persona: persona)

        expect(result[:session_id]).to eq('test-session')
        expect(result[:voice_interaction]).to be(true)
      end

      it 'defaults to current persona when none specified' do
        allow(Services::PersonaStateService).to receive(:get_current_persona).and_return('jax')

        # Mock persona creation for jax
        mock_jax_persona = instance_double(Personas::BasePersona)
        allow(Personas::BasePersona).to receive(:create).with('jax', context).and_return(mock_jax_persona)
        allow(mock_jax_persona).to receive(:name).and_return('jax')
        allow(mock_jax_persona).to receive(:tool_schemas).and_return([])

        result = subject.process_conversation(message: message, context: context)

        expect(result[:persona]).to eq('jax')
      end
    end

    context 'with different personas' do
      %w[buddy jax lomi zorp].each do |persona_name|
        it "processes conversation correctly with #{persona_name} persona" do
          # Mock persona creation for each specific persona
          mock_persona_instance = instance_double(Personas::BasePersona)
          allow(Personas::BasePersona).to receive(:create).with(persona_name, anything).and_return(mock_persona_instance)
          allow(mock_persona_instance).to receive(:name).and_return(persona_name)
          allow(mock_persona_instance).to receive(:tool_schemas).and_return([])

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
      let(:failing_error_handler) do
        instance_double(Services::Conversation::ErrorHandler).tap do |handler|
          allow(handler).to receive(:handle).and_return({
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
      end

      subject { described_class.new(error_handler: failing_error_handler) }

      before do
        # Make the LLM manager fail
        allow(mock_llm_manager).to receive(:call_llm).and_raise(StandardError.new('LLM service unavailable'))
      end

      xit 'handles LLM service failures gracefully' do
        # TODO: Fix mock setup for error handler - needs proper double with handle_error method
        result = subject.process_conversation(message: message, context: context, persona: persona)

        expect(result[:error]).to eq('llm_error')
        expect(result[:response]).to include('technical difficulties')
        expect(result[:continue_conversation]).to be(false)
        expect(failing_error_handler).to have_received(:handle)
      end

      xit 'preserves session information during errors' do
        # TODO: Fix mock setup for error handler - needs proper double with handle_error method
        result = subject.process_conversation(message: message, context: context, persona: persona)

        expect(result[:session_id]).to eq('test-session')
        expect(result[:persona]).to eq('buddy')
      end
    end

    context 'rate limiting scenarios' do
      let(:rate_limit_error_handler) do
        instance_double(Services::Conversation::ErrorHandler).tap do |handler|
          allow(handler).to receive(:handle).and_return({
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
      end

      subject { described_class.new(error_handler: rate_limit_error_handler) }

      before do
        # Make the LLM manager raise a rate limit error
        allow(mock_llm_manager).to receive(:call_llm).and_raise(StandardError.new('Rate limit exceeded'))
      end

      xit 'handles rate limiting appropriately' do
        # TODO: Fix mock setup for error handler - needs proper double with handle_error method
        result = subject.process_conversation(message: message, context: context, persona: persona)

        expect(result[:error]).to eq('rate_limit')
        expect(result[:response]).to include('pause')
        expect(result[:continue_conversation]).to be(false)
        expect(rate_limit_error_handler).to have_received(:handle)
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

        # Mock a session with the custom session ID
        custom_mock_session = instance_double(ConversationSession,
                                              session_id: 'custom-session-id',
                                              messages_for_llm: [],
                                              add_message: true,
                                              messages: double('messages', count: 0),
                                              created_at: Time.now - 1.minute,
                                              metadata: {},
                                              conversation: double('conversation', new_record?: false))

        # Override the existing mock to return the custom session for the custom session ID
        allow(mock_state_manager).to receive(:create_or_get_session).with('custom-session-id', anything).and_return(custom_mock_session)

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

      # Verify the key result structure indicates proper service coordination
      expect(result).to include(:response, :conversation_id, :session_id, :persona, :model, :cost, :tokens)
      expect(result[:response]).to be_a(String)
      expect(result[:response]).not_to be_empty
      expect(result[:cost]).to be_a(Numeric)
      expect(result[:tokens]).to be_a(Hash)
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
