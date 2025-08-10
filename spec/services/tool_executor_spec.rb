# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::ToolExecutor do
  describe '.execute' do
    context 'with a valid tool' do
      let(:tool_call) do
        {
          id: 'test_123',
          name: 'test',
          arguments: { info_type: 'battery' }
        }
      end

      it 'executes the tool and returns success' do
        results = described_class.execute([tool_call])
        result = results.first

        expect(result[:success]).to be true
        expect(result[:tool_name]).to eq('test')
        expect(result[:result]).to include('battery')
        expect(result[:tool_call_id]).to eq('test_123')
      end
    end

    context 'with invalid tool name' do
      let(:tool_call) do
        {
          id: 'invalid_123',
          name: 'nonexistent_tool',
          arguments: {}
        }
      end

      it 'returns an error result' do
        results = described_class.execute([tool_call])
        result = results.first

        expect(result[:success]).to be false
        expect(result[:error]).to include("No tool handles 'nonexistent_tool'")
        expect(result[:tool_name]).to eq('nonexistent_tool')
      end
    end

    context 'with tool execution error' do
      let(:tool_call) do
        {
          id: 'error_123',
          name: 'test',
          arguments: { info_type: 'invalid_type' }
        }
      end

      it 'catches the error and returns error result' do
        allow(TestTool).to receive(:test).and_raise(StandardError, 'Test error')

        results = described_class.execute([tool_call])
        result = results.first

        expect(result[:success]).to be false
        expect(result[:error]).to include('Test error')
      end
    end

    context 'with empty tool calls' do
      it 'returns empty array' do
        expect(described_class.execute([])).to eq([])
      end
    end

    context 'with multiple tool calls' do
      let(:tool_calls) do
        [
          { id: '1', name: 'test', arguments: { info_type: 'battery' } },
          { id: '2', name: 'test', arguments: { info_type: 'sensors' } }
        ]
      end

      it 'executes all tools and returns results array' do
        results = described_class.execute(tool_calls)

        expect(results).to be_an(Array)
        expect(results.size).to eq(2)
        expect(results.all? { |r| r[:success] }).to be true
      end
    end
  end
end
