# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::ToolExecutor do
  describe '.execute' do
    context 'with a valid tool' do
      let(:tool_call) do
        {
          id: 'speech_123',
          name: 'speak_text',
          arguments: { text: 'Hello world' }
        }
      end

      it 'executes the tool and returns success' do
        # Mock SpeechTool which should exist
        allow(SpeechTool).to receive(:speak_text).and_return('Speech synthesized: Hello world')

        results = described_class.execute([tool_call])
        result = results.first

        expect(result[:success]).to be true
        expect(result[:tool_name]).to eq('speak_text')
        expect(result[:result]).to include('Speech synthesized')
        expect(result[:tool_call_id]).to eq('speech_123')
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
          name: 'speak_text',
          arguments: { text: 'Error test' }
        }
      end

      it 'catches the error and returns error result' do
        allow(SpeechTool).to receive(:speak_text).and_raise(StandardError, 'Speech synthesis failed')

        results = described_class.execute([tool_call])
        result = results.first

        expect(result[:success]).to be false
        expect(result[:error]).to include('Speech synthesis failed')
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
          { id: '1', name: 'speak_text', arguments: { text: 'First message' } },
          { id: '2', name: 'speak_text', arguments: { text: 'Second message' } }
        ]
      end

      it 'executes all tools and returns results array' do
        allow(SpeechTool).to receive(:speak_text).with(text: 'First message').and_return('Speech 1')
        allow(SpeechTool).to receive(:speak_text).with(text: 'Second message').and_return('Speech 2')

        results = described_class.execute(tool_calls)

        expect(results).to be_an(Array)
        expect(results.size).to eq(2)
        expect(results.all? { |r| r[:success] }).to be true
      end
    end
  end
end
