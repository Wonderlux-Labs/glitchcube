# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::Conversation::FlowManager, 'create_simple_tool_summary' do
  let(:flow_manager) { described_class.new }

  describe '#create_simple_tool_summary' do
    context 'with empty tool calls' do
      it 'returns working message when no tool calls provided' do
        result = flow_manager.send(:create_simple_tool_summary, [])
        expect(result).to eq("I'm working on that...")
      end

      it 'returns working message when tool calls are nil' do
        result = flow_manager.send(:create_simple_tool_summary, nil)
        expect(result).to eq("I'm working on that...")
      end
    end

    context 'with single tool call' do
      let(:tool_call) do
        {
          tool_name: 'set_light',
          arguments: { color: 'yellow' },
          result: { success: true, result: '✅ Set all to yellow at 150' }
        }
      end

      it 'creates simple summary with result text' do
        result = flow_manager.send(:create_simple_tool_summary, [tool_call])
        expect(result).to eq('Actions taken: set_light (✅ Set all to yellow at 150)')
      end
    end

    context 'with failed tool call' do
      let(:failed_tool_call) do
        {
          tool_name: 'set_light',
          arguments: { color: 'yellow' },
          result: { success: false, error: 'Device not found' }
        }
      end

      it 'shows failure message' do
        result = flow_manager.send(:create_simple_tool_summary, [failed_tool_call])
        expect(result).to eq('Actions taken: set_light (failed: Device not found)')
      end
    end

    context 'with multiple tool calls' do
      let(:multiple_tool_calls) do
        [
          {
            tool_name: 'set_light',
            arguments: { color: 'yellow' },
            result: { success: true, result: '✅ Lights yellow' }
          },
          {
            tool_name: 'display_text',
            arguments: { text: 'Hello' },
            result: { success: true, result: '✅ Text displayed' }
          }
        ]
      end

      it 'joins multiple tool results' do
        result = flow_manager.send(:create_simple_tool_summary, multiple_tool_calls)
        expect(result).to eq('Actions taken: set_light (✅ Lights yellow), display_text (✅ Text displayed)')
      end
    end

    context 'with simple result format' do
      let(:simple_tool_call) do
        {
          tool_name: 'play_sound',
          arguments: { file: 'beep.wav' },
          result: 'Sound played successfully'
        }
      end

      it 'handles non-hash results' do
        result = flow_manager.send(:create_simple_tool_summary, [simple_tool_call])
        expect(result).to eq('Actions taken: play_sound (completed)')
      end
    end
  end
end
