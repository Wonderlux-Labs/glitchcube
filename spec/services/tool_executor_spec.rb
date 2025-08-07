# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/tool_executor'
require_relative '../../lib/tools/test_tool'

RSpec.describe Services::ToolExecutor do
  describe '.execute_single' do
    context 'with a valid tool' do
      let(:tool_call) do
        {
          id: 'test_123',
          name: 'test',
          arguments: { info_type: 'battery' }
        }
      end

      it 'executes the tool and returns success' do
        result = described_class.execute_single(tool_call)

        expect(result[:success]).to be true
        expect(result[:tool_name]).to eq('test')
        expect(result[:result]).to include('battery_level')
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
        result = described_class.execute_single(tool_call)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Tool not found')
        expect(result[:tool_name]).to eq('nonexistent_tool')
      end
    end

    context 'with tool execution error' do
      let(:tool_call) do
        {
          id: 'error_123',
          name: 'test',
          arguments: { info_type: 'battery' }
        }
      end

      it 'catches the error and returns error result' do
        allow(TestTool).to receive(:call).and_raise(StandardError, 'Test error')

        result = described_class.execute_single(tool_call)

        expect(result[:success]).to be false
        expect(result[:error]).to include('Test error')
      end
    end

    context 'with timeout' do
      let(:tool_call) do
        {
          id: 'timeout_123',
          name: 'test',
          arguments: { info_type: 'battery' }
        }
      end

      it 'times out and returns error' do
        allow(TestTool).to receive(:call) do
          sleep 5
          'Should not reach here'
        end

        result = described_class.execute_single(tool_call, timeout: 1)

        expect(result[:success]).to be false
        expect(result[:error]).to include('timed out')
      end
    end
  end

  describe '.execute' do
    context 'with multiple tool calls' do
      let(:tool_calls) do
        [
          { id: '1', name: 'test', arguments: { info_type: 'battery' } },
          { id: '2', name: 'test', arguments: { info_type: 'location' } }
        ]
      end

      it 'executes all tools and returns results array' do
        results = described_class.execute(tool_calls)

        expect(results).to be_an(Array)
        expect(results.size).to eq(2)
        expect(results[0][:result]).to include('battery')
        expect(results[1][:result]).to include('location')
      end

      context 'with parallel execution' do
        it 'executes tools in parallel' do
          start_time = Time.now
          
          # Mock tools to sleep briefly
          allow(TestTool).to receive(:call) do |info_type:|
            sleep 0.1
            "Processed: #{info_type}"
          end

          results = described_class.execute(tool_calls, parallel: true)
          duration = Time.now - start_time

          expect(results.size).to eq(2)
          # Parallel execution should be faster than sequential
          expect(duration).to be < 0.15
        end
      end
    end

    context 'with empty tool calls' do
      it 'returns empty array' do
        expect(described_class.execute([])).to eq([])
        expect(described_class.execute(nil)).to eq([])
      end
    end
  end

  describe '.normalize_arguments' do
    it 'converts string keys to symbols' do
      args = { 'message' => 'test', 'count' => 5 }
      normalized = described_class.normalize_arguments(args)

      expect(normalized).to eq({ message: 'test', count: 5 })
    end

    it 'handles nil arguments' do
      expect(described_class.normalize_arguments(nil)).to eq({})
    end

    it 'handles already symbolized keys' do
      args = { message: 'test' }
      expect(described_class.normalize_arguments(args)).to eq(args)
    end
  end

  describe '.format_for_conversation' do
    let(:results) do
      [
        { tool_name: 'test', success: true, result: 'Success message' },
        { tool_name: 'failed', success: false, error: 'Error message' }
      ]
    end

    it 'formats results for LLM consumption' do
      formatted = described_class.format_for_conversation(results)

      expect(formatted).to include('Tool: test')
      expect(formatted).to include('Result: Success message')
      expect(formatted).to include('Tool: failed')
      expect(formatted).to include('Error: Error message')
    end

    it 'handles empty results' do
      expect(described_class.format_for_conversation([])).to eq('No tool results')
    end
  end
end