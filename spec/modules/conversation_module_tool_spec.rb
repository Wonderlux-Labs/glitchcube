# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/modules/conversation_module'

RSpec.describe ConversationModule do
  let(:conversation_module) { ConversationModule.new }

  describe '#handle_native_tool_response' do
    let(:messages) do
      [
        { role: 'system', content: 'You are a helpful assistant.' },
        { role: 'user', content: 'Turn on the lights' }
      ]
    end

    let(:llm_options) do
      {
        model: 'gpt-4',
        temperature: 0.7,
        max_tokens: 500
      }
    end

    let(:response_schema) do
      {
        type: 'object',
        properties: {
          response: { type: 'string' },
          continue_conversation: { type: 'boolean' }
        }
      }
    end

    let(:tool_calls) do
      [
        {
          'id' => 'call_123',
          'function' => {
            'name' => 'set_lights',
            'arguments' => '{"state":"on","brightness":100}'
          }
        }.with_indifferent_access
      ]
    end

    let(:llm_response) do
      response = double('LLMResponse')
      allow(response).to receive(:tool_calls).and_return(tool_calls)
      allow(response).to receive(:function_calls).and_return([{ id: 'call_123', name: 'set_lights' }])
      allow(response).to receive(:function_arguments_for) do |name|
        name == 'set_lights' ? { 'state' => 'on', 'brightness' => 100 } : nil
      end
      allow(response).to receive(:message_data).and_return({ role: 'assistant', content: nil, tool_calls: tool_calls })
      response
    end

    let(:follow_up_response) do
      double('LLMResponse',
             response_text: 'I turned on the lights for you.',
             content: 'I turned on the lights for you.',
             continue_conversation?: false,
             model: 'gpt-4',
             usage: { prompt_tokens: 100, completion_tokens: 50 },
             cost: 0.01)
    end

    before do
      allow(Services::System::ToolExecutor).to receive(:execute)
        .with([{ name: 'set_lights', arguments: { 'state' => 'on', 'brightness' => 100 } }])
        .and_return([{ success: true, message: 'Lights turned on' }])

      allow(Services::Llm::LLMService).to receive(:complete_with_messages)
        .and_return(follow_up_response)

      allow(Services::Logging::SimpleLogger).to receive(:info)
    end

    it 'executes tool calls and returns a follow-up response' do
      result = conversation_module.send(:handle_native_tool_response, llm_response, messages, llm_options, response_schema)

      expect(result).to eq(follow_up_response)
    end

    it 'tracks tool calls in @last_tool_calls' do
      conversation_module.send(:handle_native_tool_response, llm_response, messages, llm_options, response_schema)

      expect(conversation_module.instance_variable_get(:@last_tool_calls)).to eq([
                                                                                   {
                                                                                     tool_name: 'set_lights',
                                                                                     arguments: { 'state' => 'on', 'brightness' => 100 },
                                                                                     result: { success: true, message: 'Lights turned on' }
                                                                                   }
                                                                                 ])
    end

    it 'includes tool results in follow-up messages' do
      expected_tool_result = {
        tool_call_id: 'call_123',
        role: 'tool',
        name: 'set_lights',
        content: '{"success":true,"message":"Lights turned on"}'
      }

      expect(Services::Llm::LLMService).to receive(:complete_with_messages) do |args|
        expect(args[:messages]).to include(expected_tool_result)
        follow_up_response
      end

      conversation_module.send(:handle_native_tool_response, llm_response, messages, llm_options, response_schema)
    end

    it 'uses structured output in follow-up call when schema provided' do
      # Mock that the model supports structured output
      allow(GlitchCube::ModelPresets).to receive(:supports_structured_output?).and_return(true)

      expect(Services::Llm::LLMService).to receive(:complete_with_messages) do |args|
        expect(args[:response_format]).not_to be_nil
        follow_up_response
      end

      conversation_module.send(:handle_native_tool_response, llm_response, messages, llm_options, response_schema)
    end

    it 'handles multiple tool calls' do
      multi_tool_calls = [
        {
          'id' => 'call_123',
          'function' => {
            'name' => 'set_lights',
            'arguments' => '{"state":"on"}'
          }
        }.with_indifferent_access,
        {
          'id' => 'call_456',
          'function' => {
            'name' => 'speak',
            'arguments' => '{"text":"Hello"}'
          }
        }.with_indifferent_access
      ]

      multi_llm_response = double('LLMResponse')
      allow(multi_llm_response).to receive(:tool_calls).and_return(multi_tool_calls)
      allow(multi_llm_response).to receive(:function_calls).and_return([
                                                                         { id: 'call_123', name: 'set_lights' },
                                                                         { id: 'call_456', name: 'speak' }
                                                                       ])
      allow(multi_llm_response).to receive(:function_arguments_for) do |name|
        case name
        when 'set_lights' then { 'state' => 'on' }
        when 'speak' then { 'text' => 'Hello' }
        end
      end
      allow(multi_llm_response).to receive(:message_data).and_return({ role: 'assistant', content: nil, tool_calls: multi_tool_calls })

      allow(Services::System::ToolExecutor).to receive(:execute)
        .with([{ name: 'set_lights', arguments: { 'state' => 'on' } }])
        .and_return([{ success: true }])

      allow(Services::System::ToolExecutor).to receive(:execute)
        .with([{ name: 'speak', arguments: { 'text' => 'Hello' } }])
        .and_return([{ success: true, spoken: 'Hello' }])

      conversation_module.send(:handle_native_tool_response, multi_llm_response, messages, llm_options, response_schema)

      last_tool_calls = conversation_module.instance_variable_get(:@last_tool_calls)
      expect(last_tool_calls.length).to eq(2)
      expect(last_tool_calls.map { |c| c[:tool_name] }).to eq(%w[set_lights speak])
    end

    it 'handles JSON parsing errors gracefully' do
      invalid_tool_calls = [
        {
          'id' => 'call_789',
          'function' => {
            'name' => 'set_lights',
            'arguments' => 'invalid json {'
          }
        }.with_indifferent_access
      ]

      invalid_llm_response = double('LLMResponse')
      allow(invalid_llm_response).to receive(:tool_calls).and_return(invalid_tool_calls)
      allow(invalid_llm_response).to receive(:function_calls).and_return([{ id: 'call_789', name: 'set_lights' }])
      allow(invalid_llm_response).to receive(:function_arguments_for).and_return(nil)  # Returns nil for unparseable JSON
      allow(invalid_llm_response).to receive(:message_data).and_return({ role: 'assistant', content: nil, tool_calls: invalid_tool_calls })

      # Tool executor should not be called when arguments can't be parsed
      expect(Services::System::ToolExecutor).not_to receive(:execute)

      expect do
        conversation_module.send(:handle_native_tool_response, invalid_llm_response, messages, llm_options, response_schema)
      end.not_to raise_error
    end
  end
end
