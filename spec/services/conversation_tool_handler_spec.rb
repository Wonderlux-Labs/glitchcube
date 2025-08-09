# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/conversation_tool_handler'

RSpec.describe Services::ConversationToolHandler do
  let(:mock_session) do
    instance_double(
      Services::ConversationSession,
      session_id: 'test-session-123',
      add_message: double('message', role: 'assistant', content: 'test')
    )
  end
  let(:persona) { 'buddy' }
  let(:handler) { described_class.new(session: mock_session, persona: persona) }

  describe '#load_tools_for_persona' do
    it 'returns provided tools if present' do
      provided_tools = [{ 'name' => 'test_tool' }]
      result = handler.load_tools_for_persona(provided_tools: provided_tools)
      expect(result).to eq(provided_tools)
    end

    it 'loads tools for persona if none provided' do
      expected_tools = [
        {
          'type' => 'function',
          'function' => {
            'name' => 'speech_synthesis',
            'description' => 'Speech synthesis tool - speech_synthesis',
            'parameters' => { 'type' => 'object', 'properties' => {} }
          }
        }
      ]

      allow(Services::ToolRegistryService).to receive(:get_tools_for_character)
        .with(persona)
        .and_return(expected_tools)

      result = handler.load_tools_for_persona(provided_tools: nil)
      expect(result).to eq(expected_tools)
    end
  end

  describe '#configure_llm_options' do
    let(:base_options) { { model: 'test-model', temperature: 0.7 } }

    it 'returns base options if no tools provided' do
      result = handler.configure_llm_options(base_options, nil)
      expect(result).to eq(base_options)
    end

    it 'merges tool configuration when tools provided' do
      tools = [{ 'name' => 'test_tool' }]

      result = handler.configure_llm_options(base_options, tools)

      expect(result).to eq({
                             model: 'test-model',
                             temperature: 0.7,
                             tools: tools,
                             tool_choice: 'auto',
                             parallel_tool_calls: true
                           })
    end

    it 'preserves provided tool options' do
      tools = [{ 'name' => 'test_tool' }]
      options_with_tool_config = base_options.merge(
        tool_choice: 'required',
        parallel_tool_calls: false
      )

      result = handler.configure_llm_options(options_with_tool_config, tools)

      expect(result[:tool_choice]).to eq('required')
      expect(result[:parallel_tool_calls]).to be false
    end
  end

  describe '#handle_tool_calls' do
    let(:messages) { [{ role: 'user', content: 'test message' }] }
    let(:llm_options) { { model: 'test-model' } }

    context 'when no tool calls present' do
      let(:mock_llm_response) do
        instance_double(Services::LLMResponse, has_tool_calls?: false)
      end

      it 'returns original response unchanged' do
        result = handler.handle_tool_calls(mock_llm_response, messages, llm_options)
        expect(result).to eq(mock_llm_response)
      end
    end

    context 'when tool calls present' do
      let(:tool_calls) do
        [
          {
            id: 'call_123',
            type: 'function',
            function: { name: 'speech_synthesis', arguments: '{"text": "Hello"}' }
          }
        ]
      end

      let(:mock_llm_response) do
        instance_double(
          Services::LLMResponse,
          has_tool_calls?: true,
          tool_calls: tool_calls,
          content: 'I will speak this message'
        )
      end

      let(:tool_results) do
        [
          {
            tool_call_id: 'call_123',
            tool_name: 'speech_synthesis',
            success: true,
            result: 'Speech synthesis completed'
          }
        ]
      end

      before do
        allow(Services::ToolExecutor).to receive(:execute)
          .with(tool_calls, timeout: 10)
          .and_return(tool_results)

        allow(Services::LoggerService).to receive(:log_api_call)
        allow(Services::LLMService).to receive(:complete_with_messages)
          .and_return(instance_double(Services::LLMResponse, content: 'Follow up response'))
      end

      it 'executes tool calls and logs results' do
        expect(Services::ToolExecutor).to receive(:execute).with(tool_calls, timeout: 10)
        expect(Services::LoggerService).to receive(:log_api_call).with(
          service: 'tool_executor',
          endpoint: 'speech_synthesis',
          method: 'execute',
          status: 200,
          session_id: 'test-session-123',
          persona: persona
        )

        handler.handle_tool_calls(mock_llm_response, messages, llm_options)
      end

      it 'continues conversation with tool results' do
        mock_follow_up_response = instance_double(Services::LLMResponse, content: 'Follow up response')

        expect(Services::LLMService).to receive(:complete_with_messages) do |args|
          expect(args[:messages]).to include(
            hash_including(role: 'assistant', tool_calls: tool_calls),
            hash_including(role: 'tool', content: 'speech_synthesis: Speech synthesis completed')
          )
          mock_follow_up_response
        end

        result = handler.handle_tool_calls(mock_llm_response, messages, llm_options)
        expect(result).to eq(mock_follow_up_response)
      end

      it 'saves tool interaction to session' do
        expect(mock_session).to receive(:add_message).twice

        handler.handle_tool_calls(mock_llm_response, messages, llm_options)
      end

      it 'tracks tool calls made' do
        handler.handle_tool_calls(mock_llm_response, messages, llm_options)
        expect(handler.last_tool_calls_made).to eq(['speech_synthesis'])
      end
    end

    context 'when tool execution fails' do
      let(:mock_llm_response) do
        instance_double(
          Services::LLMResponse,
          has_tool_calls?: true,
          tool_calls: [{ id: 'call_123', name: 'failing_tool' }]
        )
      end

      before do
        allow(Services::ToolExecutor).to receive(:execute)
          .and_raise(StandardError, 'Tool execution failed')
      end

      it 'handles tool execution errors gracefully' do
        expect do
          handler.handle_tool_calls(mock_llm_response, messages, llm_options)
        end.not_to raise_error
      end

      it 'returns original response when tool execution fails' do
        result = handler.handle_tool_calls(mock_llm_response, messages, llm_options)
        expect(result).to eq(mock_llm_response)
      end
    end
  end

  describe '#last_tool_calls_made' do
    it 'returns empty array when no tool calls made' do
      expect(handler.last_tool_calls_made).to eq([])
    end
  end
end
