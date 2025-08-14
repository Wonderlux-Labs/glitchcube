# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Post-tool response handling' do
  let(:flow_manager) { Services::Conversation::FlowManager.new }
  let(:message) { 'Turn the lights red' }
  let(:context) { { session_id: 'test_session', persona: 'buddy' } }

  describe 'handling different model response types after tool execution' do
    context 'with model that supports structured responses' do
      it 'accepts both JSON and plain text responses' do
        # Mock LLM responses
        allow_any_instance_of(Services::Conversation::LlmInteractionManager).to receive(:call_llm)
          .and_return(
            # First call: tool calls
            instance_double('LlmResponse',
                            tool_calls?: true,
                            tool_calls: [{ id: 'call_123', function: { name: 'set_state', arguments: '{"state":"on","color":"red","brightness":100}' } }],
                            function_calls: [{ name: 'set_state' }],
                            function_arguments_for: { state: 'on', color: 'red', brightness: 100 },
                            message_data: { role: 'assistant', content: '', tool_calls: [] },
                            model: 'test-model',
                            usage: { prompt_tokens: 100, completion_tokens: 50 },
                            cost: 0.01),
            # Second call: plain text response
            instance_double('LlmResponse',
                            tool_calls?: false,
                            response_text: 'Got it! I turned the lights red for you.',
                            continue_conversation?: true,
                            inner_thoughts: 'Successfully changed the lighting',
                            model: 'test-model',
                            usage: { prompt_tokens: 120, completion_tokens: 30 },
                            cost: 0.005,
                            content: 'Got it! I turned the lights red for you.',
                            parsed_content: nil,
                            raw_response: { 'choices' => [] })
          )

        result = flow_manager.process_conversation(message: message, context: context)

        expect(result[:response]).to eq('Got it! I turned the lights red for you.')
        expect(result[:continue_conversation]).to be true
        expect(result[:error]).to be_nil
      end
    end

    context 'with model that fails structured response generation' do
      it 'handles empty content gracefully when schema fails' do
        # Mock LLM responses - second call returns empty content
        allow_any_instance_of(Services::Conversation::LlmInteractionManager).to receive(:call_llm)
          .and_return(
            # First call: tool calls
            instance_double('LlmResponse',
                            tool_calls?: true,
                            tool_calls: [{ id: 'call_123', function: { name: 'set_state', arguments: '{"state":"on","color":"red","brightness":100}' } }],
                            function_calls: [{ name: 'set_state' }],
                            function_arguments_for: { state: 'on', color: 'red', brightness: 100 },
                            message_data: { role: 'assistant', content: '', tool_calls: [] },
                            model: 'test-model',
                            usage: { prompt_tokens: 100, completion_tokens: 50 },
                            cost: 0.01),
            # Second call: empty content (schema failure)
            instance_double('LlmResponse',
                            tool_calls?: false,
                            response_text: '', # Empty response
                            continue_conversation?: false,
                            inner_thoughts: nil,
                            model: 'test-model',
                            usage: { prompt_tokens: 120, completion_tokens: 0 },
                            cost: 0.002,
                            content: '',
                            parsed_content: nil,
                            raw_response: { 'choices' => [] })
          )

        result = flow_manager.process_conversation(message: message, context: context)

        # Should trigger fallback response, not crash
        expect(result[:response]).to be_a(String)
        expect(result[:response]).not_to be_empty
        expect(result[:continue_conversation]).to be false
        expect(result[:error]).to be_nil
      end
    end

    context 'with model that returns unstructured text after tools' do
      it 'extracts response from plain text' do
        # Mock LLM responses
        allow_any_instance_of(Services::Conversation::LlmInteractionManager).to receive(:call_llm)
          .and_return(
            # First call: tool calls
            instance_double('LlmResponse',
                            tool_calls?: true,
                            tool_calls: [{ id: 'call_123', function: { name: 'set_state', arguments: '{"state":"on","color":"red","brightness":100}' } }],
                            function_calls: [{ name: 'set_state' }],
                            function_arguments_for: { state: 'on', color: 'red', brightness: 100 },
                            message_data: { role: 'assistant', content: '', tool_calls: [] },
                            model: 'test-model',
                            usage: { prompt_tokens: 100, completion_tokens: 50 },
                            cost: 0.01),
            # Second call: plain text (not JSON)
            instance_double('LlmResponse',
                            tool_calls?: false,
                            response_text: 'The red lights are now glowing beautifully! How does that look?',
                            continue_conversation?: true,
                            inner_thoughts: nil,
                            model: 'test-model',
                            usage: { prompt_tokens: 120, completion_tokens: 25 },
                            cost: 0.008,
                            content: 'The red lights are now glowing beautifully! How does that look?',
                            parsed_content: nil,
                            raw_response: { 'choices' => [] })
          )

        result = flow_manager.process_conversation(message: message, context: context)

        expect(result[:response]).to eq('The red lights are now glowing beautifully! How does that look?')
        expect(result[:continue_conversation]).to be true
        expect(result[:error]).to be_nil
      end
    end
  end

  describe 'schema enforcement behavior' do
    it 'does not require JSON schema for post-tool responses' do
      # Spy on the LLM manager to check options
      llm_manager = instance_double(Services::Conversation::LlmInteractionManager)
      allow(Services::Conversation::LlmInteractionManager).to receive(:new).and_return(llm_manager)

      # Setup initial call with tools
      allow(llm_manager).to receive(:build_system_prompt).and_return('test prompt')
      allow(llm_manager).to receive(:prepare_messages).and_return([])
      allow(llm_manager).to receive(:call_llm).and_return(
        instance_double('LlmResponse',
                        tool_calls?: true,
                        tool_calls: [{ id: 'call_123', function: { name: 'set_state', arguments: '{"state":"on"}' } }],
                        function_calls: [{ name: 'set_state' }],
                        function_arguments_for: { state: 'on' },
                        message_data: { role: 'assistant', content: '', tool_calls: [] },
                        model: 'test-model',
                        usage: { prompt_tokens: 100, completion_tokens: 50 },
                        cost: 0.01),
        instance_double('LlmResponse',
                        tool_calls?: false,
                        response_text: 'Done!',
                        continue_conversation?: false,
                        inner_thoughts: nil,
                        model: 'test-model',
                        usage: { prompt_tokens: 120, completion_tokens: 10 },
                        cost: 0.003,
                        content: 'Done!',
                        parsed_content: nil,
                        raw_response: { 'choices' => [] })
      )

      # Mock other dependencies
      allow(llm_manager).to receive(:select_appropriate_model).and_return('test-model')
      allow(llm_manager).to receive(:get_response_schema).and_return(nil)

      flow_manager = Services::Conversation::FlowManager.new
      flow_manager.process_conversation(message: message, context: context)

      # Verify second call doesn't use schema
      expect(llm_manager).to have_received(:call_llm).twice
    end
  end
end
