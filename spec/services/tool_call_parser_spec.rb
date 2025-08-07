# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/tool_call_parser'
require_relative '../../lib/services/llm_response'

RSpec.describe Services::ToolCallParser do
  describe '.parse' do
    context 'with tool calls in response' do
      let(:raw_response) do
        {
          choices: [{
            message: {
              content: 'I will check the sensors for you.',
              tool_calls: [
                {
                  id: 'call_abc123',
                  type: 'function',
                  function: {
                    name: 'home_assistant',
                    arguments: '{"action": "get_sensors", "params": {}}'
                  }
                }
              ]
            }
          }],
          usage: { prompt_tokens: 100, completion_tokens: 50 }
        }
      end

      let(:llm_response) { Services::LLMResponse.new(raw_response) }

      it 'parses tool calls from LLM response' do
        tool_calls = described_class.parse(llm_response)

        expect(tool_calls).to be_an(Array)
        expect(tool_calls.size).to eq(1)

        call = tool_calls.first
        expect(call[:id]).to eq('call_abc123')
        expect(call[:type]).to eq('function')
        expect(call[:name]).to eq('home_assistant')
        expect(call[:arguments]).to eq({ action: 'get_sensors', params: {} })
      end
    end

    context 'with multiple tool calls' do
      let(:raw_response) do
        {
          choices: [{
            message: {
              tool_calls: [
                {
                  id: 'call_1',
                  function: { name: 'test', arguments: '{"message": "first"}' }
                },
                {
                  id: 'call_2',
                  function: { name: 'test', arguments: '{"message": "second"}' }
                }
              ]
            }
          }]
        }
      end

      let(:llm_response) { Services::LLMResponse.new(raw_response) }

      it 'parses all tool calls' do
        tool_calls = described_class.parse(llm_response)

        expect(tool_calls.size).to eq(2)
        expect(tool_calls[0][:name]).to eq('test')
        expect(tool_calls[0][:arguments][:message]).to eq('first')
        expect(tool_calls[1][:arguments][:message]).to eq('second')
      end
    end

    context 'with no tool calls' do
      let(:raw_response) do
        {
          choices: [{
            message: {
              content: 'Just a regular response without tools.'
            }
          }]
        }
      end

      let(:llm_response) { Services::LLMResponse.new(raw_response) }

      it 'returns empty array' do
        expect(described_class.parse(llm_response)).to eq([])
      end
    end

    context 'with malformed arguments' do
      let(:raw_response) do
        {
          choices: [{
            message: {
              tool_calls: [
                {
                  id: 'call_bad',
                  function: {
                    name: 'test',
                    arguments: 'not valid json'
                  }
                }
              ]
            }
          }]
        }
      end

      let(:llm_response) { Services::LLMResponse.new(raw_response) }

      it 'attempts to extract arguments with fallback' do
        tool_calls = described_class.parse(llm_response)

        expect(tool_calls.size).to eq(1)
        expect(tool_calls[0][:name]).to eq('test')
        # Fallback parser should return empty hash for unparseable content
        expect(tool_calls[0][:arguments]).to be_a(Hash)
      end
    end
  end

  describe '.parse_single_tool_call' do
    context 'with valid tool call' do
      let(:tool_call) do
        {
          id: 'test_id',
          type: 'function',
          function: {
            name: 'my_tool',
            arguments: '{"key": "value"}'
          }
        }
      end

      it 'parses the tool call correctly' do
        result = described_class.parse_single_tool_call(tool_call)

        expect(result[:id]).to eq('test_id')
        expect(result[:type]).to eq('function')
        expect(result[:name]).to eq('my_tool')
        expect(result[:arguments]).to eq({ key: 'value' })
      end
    end

    context 'with missing id' do
      let(:tool_call) do
        {
          function: { name: 'my_tool', arguments: '{}' }
        }
      end

      it 'generates an id' do
        result = described_class.parse_single_tool_call(tool_call)

        expect(result[:id]).to start_with('tool_')
        expect(result[:name]).to eq('my_tool')
      end
    end

    context 'with hash arguments' do
      let(:tool_call) do
        {
          function: {
            name: 'my_tool',
            arguments: { already: 'parsed' }
          }
        }
      end

      it 'uses arguments as-is' do
        result = described_class.parse_single_tool_call(tool_call)

        expect(result[:arguments]).to eq({ already: 'parsed' })
      end
    end

    context 'with nil arguments' do
      let(:tool_call) do
        {
          function: { name: 'my_tool', arguments: nil }
        }
      end

      it 'returns empty hash for arguments' do
        result = described_class.parse_single_tool_call(tool_call)

        expect(result[:arguments]).to eq({})
      end
    end
  end

  describe '.extract_fallback_arguments' do
    it 'extracts key-value pairs from malformed JSON' do
      input = 'action: "get_sensors", params: "{}"'
      result = described_class.extract_fallback_arguments(input)

      expect(result[:action]).to eq('get_sensors')
      expect(result[:params]).to eq('{}')
    end

    it 'handles unquoted values' do
      input = 'count: 5, enabled: true'
      result = described_class.extract_fallback_arguments(input)

      expect(result[:count]).to eq('5')
      expect(result[:enabled]).to eq('true')
    end
  end

  describe '.tool_available?' do
    it 'returns true for existing tools' do
      # TestTool should exist in test environment
      expect(described_class.tool_available?('test')).to be true
    end

    it 'returns false for non-existent tools' do
      expect(described_class.tool_available?('nonexistent')).to be false
    end
  end

  describe '.format_for_logging' do
    let(:tool_calls) do
      [
        { name: 'tool1', arguments: { key: 'value' } },
        { name: 'tool2', arguments: { action: 'test' } }
      ]
    end

    it 'formats tool calls for logging' do
      formatted = described_class.format_for_logging(tool_calls)

      expect(formatted).to include('tool1')
      expect(formatted).to include('tool2')
      expect(formatted).to include('key')
      expect(formatted).to include('value')
    end

    it 'handles empty array' do
      expect(described_class.format_for_logging([])).to eq('No tool calls')
    end
  end
end
