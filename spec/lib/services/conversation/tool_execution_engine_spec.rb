# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::Conversation::ToolExecutionEngine do
  include_context 'with_full_conversation_setup'

  subject { described_class.new }

  let(:session_id) { 'test-session-123' }
  let(:tool_call_id) { 'call_test_123' }

  # Mock LLM response with tool calls that should be executable
  let(:llm_response) do
    instance_double('LLMResponse',
                    tool_calls: [
                      { id: tool_call_id, function: { name: 'turn_on_light', arguments: '{"entity_id": "light.cube"}' } }
                    ],
                    function_calls: [
                      { name: 'turn_on_light', arguments: { entity_id: 'light.cube' } }
                    ])
  end

  # Setup successful tool execution by default
  before do
    # Mock ToolExecutor.execute to return successful results
    allow(Services::System::ToolExecutor).to receive(:execute).and_return([
                                                                            { success: true, entity_id: 'light.cube', message: 'Light turned on successfully' }
                                                                          ])

    # Mock function_arguments_for method on llm_response
    allow(llm_response).to receive(:function_arguments_for)
      .with('turn_on_light')
      .and_return({ entity_id: 'light.cube' })
  end

  describe '#execute_tool_calls' do
    context 'with successful tool execution' do
      it 'returns a hash with tool_results and last_tool_calls' do
        result = subject.execute_tool_calls(llm_response, session_id)

        expect(result).to be_a(Hash)
        expect(result).to have_key(:tool_results)
        expect(result).to have_key(:last_tool_calls)
      end

      it 'formats tool results properly for LLM consumption' do
        result = subject.execute_tool_calls(llm_response, session_id)
        tool_result = result[:tool_results].first

        expect(tool_result).to include(
          tool_call_id: tool_call_id,
          role: 'tool',
          name: 'turn_on_light',
          content: String
        )
      end

      it 'tracks last tool calls for context' do
        result = subject.execute_tool_calls(llm_response, session_id)
        last_call = result[:last_tool_calls].first

        expect(last_call).to include(
          tool_name: 'turn_on_light',
          arguments: { entity_id: 'light.cube' },
          result: Hash
        )
      end

      it 'delegates tool execution to ToolExecutor service' do
        subject.execute_tool_calls(llm_response, session_id)

        expect(Services::System::ToolExecutor).to have_received(:execute)
          .with([{ name: 'turn_on_light', arguments: { entity_id: 'light.cube' } }])
      end

      it 'serializes hash results as JSON for LLM consumption' do
        result = subject.execute_tool_calls(llm_response, session_id)
        tool_result = result[:tool_results].first

        expect { JSON.parse(tool_result[:content]) }.not_to raise_error
      end
    end

    context 'with empty tool calls' do
      let(:empty_llm_response) do
        instance_double('LLMResponse', tool_calls: [], function_calls: [])
      end

      it 'returns empty results gracefully' do
        result = subject.execute_tool_calls(empty_llm_response, session_id)

        expect(result[:tool_results]).to be_empty
        expect(result[:last_tool_calls]).to be_empty
      end
    end

    context 'with argument parsing errors' do
      before do
        allow(llm_response).to receive(:function_arguments_for)
          .with('turn_on_light')
          .and_return(nil) # Simulate parsing failure
      end

      it 'creates error results for unparseable arguments' do
        result = subject.execute_tool_calls(llm_response, session_id)
        tool_result = result[:tool_results].first

        expect(tool_result).to include(
          tool_call_id: tool_call_id,
          role: 'tool',
          name: 'turn_on_light'
        )

        parsed_content = JSON.parse(tool_result[:content])
        expect(parsed_content).to have_key('error')
      end

      it 'does not call ToolExecutor for unparseable arguments' do
        subject.execute_tool_calls(llm_response, session_id)

        expect(Services::System::ToolExecutor).not_to have_received(:execute)
      end
    end

    context 'with tool execution errors' do
      let(:tool_error) { StandardError.new('Tool execution failed') }

      before do
        allow(Services::System::ToolExecutor).to receive(:execute)
          .and_raise(tool_error)
      end

      it 'raises ToolExecutionError with context' do
        expect { subject.execute_tool_calls(llm_response, session_id) }
          .to raise_error(Services::Conversation::Errors::ToolExecutionError) do |error|
            expect(error.tool_name).to eq('turn_on_light')
            expect(error.original_error).to eq(tool_error)
          end
      end

      it 'logs the error before re-raising' do
        expect { subject.execute_tool_calls(llm_response, session_id) }
          .to raise_error(Services::Conversation::Errors::ToolExecutionError)

        expect(Services::Logging::SimpleLogger).to have_received(:log_error)
          .with(hash_including(
                  error: tool_error,
                  message: match(/Error executing tool: turn_on_light/),
                  session_id: session_id,
                  tool_name: 'turn_on_light'
                ))
      end
    end

    context 'with multiple tool calls' do
      let(:multi_tool_response) do
        instance_double('LLMResponse',
                        tool_calls: [
                          { id: 'call_1', function: { name: 'turn_on_light', arguments: '{}' } },
                          { id: 'call_2', function: { name: 'set_volume', arguments: '{}' } }
                        ],
                        function_calls: [
                          { name: 'turn_on_light', arguments: {} },
                          { name: 'set_volume', arguments: {} }
                        ])
      end

      before do
        allow(multi_tool_response).to receive(:function_arguments_for)
          .with('turn_on_light').and_return({})
        allow(multi_tool_response).to receive(:function_arguments_for)
          .with('set_volume').and_return({})

        # Mock multiple tool executions
        allow(Services::System::ToolExecutor).to receive(:execute)
          .and_return([{ success: true }])
      end

      it 'processes all tool calls in sequence' do
        result = subject.execute_tool_calls(multi_tool_response, session_id)

        expect(result[:tool_results].size).to eq(2)
        expect(result[:last_tool_calls].size).to eq(2)
      end

      it 'calls ToolExecutor for each tool separately' do
        subject.execute_tool_calls(multi_tool_response, session_id)

        expect(Services::System::ToolExecutor).to have_received(:execute)
          .with([{ name: 'turn_on_light', arguments: {} }])
        expect(Services::System::ToolExecutor).to have_received(:execute)
          .with([{ name: 'set_volume', arguments: {} }])
      end
    end

    context 'with different result types' do
      context 'when tool returns string result' do
        before do
          allow(Services::System::ToolExecutor).to receive(:execute)
            .and_return(['Simple string result'])
        end

        it 'converts string results to string content' do
          result = subject.execute_tool_calls(llm_response, session_id)
          tool_result = result[:tool_results].first

          expect(tool_result[:content]).to eq('Simple string result')
        end
      end

      context 'when tool returns hash result' do
        before do
          allow(Services::System::ToolExecutor).to receive(:execute)
            .and_return([{ status: 'completed', data: { value: 42 } }])
        end

        it 'converts hash results to JSON content' do
          result = subject.execute_tool_calls(llm_response, session_id)
          tool_result = result[:tool_results].first

          parsed_content = JSON.parse(tool_result[:content])
          expect(parsed_content).to include('status' => 'completed')
          expect(parsed_content['data']).to include('value' => 42)
        end
      end
    end
  end

  describe 'performance and timing' do
    it 'tracks execution duration in logs' do
      subject.execute_tool_calls(llm_response, session_id)

      expect(Services::Logging::SimpleLogger).to have_received(:info)
        .with(match(/Finished tool execution cycle in \d+ms/),
              hash_including(tagged: include(:conversation, :tools), duration_ms: Integer))
    end
  end
end
