# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::Conversation::FlowManager, 'convert_tool_history_to_english' do
  let(:flow_manager) { described_class.new }

  describe '#convert_tool_history_to_english' do
    context 'with empty messages array' do
      it 'returns empty array when no messages provided' do
        result = flow_manager.send(:convert_tool_history_to_english, [], [])
        expect(result).to eq([])
      end

      it 'returns empty array when messages are nil' do
        result = flow_manager.send(:convert_tool_history_to_english, nil, [])
        expect(result).to eq([])
      end
    end

    context 'with messages containing no tool calls' do
      let(:regular_messages) do
        [
          { role: 'system', content: 'You are a helpful assistant' },
          { role: 'user', content: 'Hello, how are you?' },
          { role: 'assistant', content: 'I am doing well, thank you!' }
        ]
      end

      it 'passes through regular messages unchanged when no tools executed' do
        result = flow_manager.send(:convert_tool_history_to_english, regular_messages, [])
        expect(result).to eq(regular_messages)
      end

      it 'preserves message order for regular messages' do
        result = flow_manager.send(:convert_tool_history_to_english, regular_messages, [])
        expect(result.map { |m| m[:role] }).to eq(['system', 'user', 'assistant'])
      end
    end

    context 'with messages containing tool_calls (the 400 error scenario)' do
      let(:messages_with_tool_calls) do
        [
          { role: 'system', content: 'You are a helpful assistant' },
          { role: 'user', content: 'Turn the lights yellow' },
          {
            role: 'assistant',
            content: nil,
            tool_calls: [
              {
                id: 'call_123',
                type: 'function',
                function: {
                  name: 'set_light_state',
                  arguments: '{"state": "on", "color": "yellow"}'
                }
              }
            ]
          },
          {
            role: 'tool',
            tool_call_id: 'call_123',
            name: 'set_light_state',
            content: '{"success": true, "result": "✅ Set all lights to yellow"}'
          }
        ]
      end

      let(:executed_tools) do
        [
          {
            tool_name: 'set_light_state',
            arguments: { state: 'on', color: 'yellow' },
            result: { success: true, result: '✅ Set all lights to yellow' }
          }
        ]
      end

      it 'filters out messages with tool_calls key' do
        result = flow_manager.send(:convert_tool_history_to_english, messages_with_tool_calls, executed_tools)

        expect(result.none? { |msg| msg.key?(:tool_calls) }).to be true
      end

      it 'filters out messages with tool_call_id key' do
        result = flow_manager.send(:convert_tool_history_to_english, messages_with_tool_calls, executed_tools)

        expect(result.none? { |msg| msg.key?(:tool_call_id) }).to be true
      end

      it 'preserves system and user messages' do
        result = flow_manager.send(:convert_tool_history_to_english, messages_with_tool_calls, executed_tools)

        system_msg = result.find { |msg| msg[:role] == 'system' }
        user_msg = result.find { |msg| msg[:role] == 'user' }

        expect(system_msg[:content]).to eq('You are a helpful assistant')
        expect(user_msg[:content]).to eq('Turn the lights yellow')
      end

      it 'adds a clean summary message for executed tools' do
        result = flow_manager.send(:convert_tool_history_to_english, messages_with_tool_calls, executed_tools)

        summary_msg = result.last
        expect(summary_msg[:role]).to eq('user')
        expect(summary_msg[:content]).to include('Actions completed:')
        expect(summary_msg[:content]).to include('set_light_state')
        expect(summary_msg[:content]).to include('✅ Set all lights to yellow')
      end

      it 'formats tool summary correctly' do
        result = flow_manager.send(:convert_tool_history_to_english, messages_with_tool_calls, executed_tools)

        summary_msg = result.last
        expect(summary_msg[:content]).to eq('Actions completed: set_light_state (✅ Set all lights to yellow)')
      end
    end

    context 'with multiple tool executions' do
      let(:messages_with_multiple_tools) do
        [
          { role: 'user', content: 'Set up the room' },
          {
            role: 'assistant',
            tool_calls: [
              { id: 'call_1', type: 'function', function: { name: 'set_lights' } },
              { id: 'call_2', type: 'function', function: { name: 'play_music' } }
            ]
          },
          {
            role: 'tool',
            tool_call_id: 'call_1',
            name: 'set_lights',
            content: '{"success": true}'
          },
          {
            role: 'tool',
            tool_call_id: 'call_2',
            name: 'play_music',
            content: '{"success": true}'
          }
        ]
      end

      let(:multiple_executed_tools) do
        [
          {
            tool_name: 'set_lights',
            arguments: { brightness: 100 },
            result: { success: true, result: 'Lights set to full brightness' }
          },
          {
            tool_name: 'play_music',
            arguments: { volume: 50 },
            result: { success: true, result: 'Music started at 50% volume' }
          }
        ]
      end

      it 'creates a summary with all tool executions' do
        result = flow_manager.send(:convert_tool_history_to_english, messages_with_multiple_tools, multiple_executed_tools)

        summary_msg = result.last
        expect(summary_msg[:content]).to include('set_lights (Lights set to full brightness)')
        expect(summary_msg[:content]).to include('play_music (Music started at 50% volume)')
      end

      it 'joins multiple tool summaries with commas' do
        result = flow_manager.send(:convert_tool_history_to_english, messages_with_multiple_tools, multiple_executed_tools)

        summary_msg = result.last
        expect(summary_msg[:content]).to match(/set_lights \([^)]+\), play_music \([^)]+\)/)
      end
    end

    context 'with edge cases in tool results' do
      let(:basic_messages) do
        [
          { role: 'user', content: 'Test' },
          {
            role: 'assistant',
            tool_calls: [{ id: 'call_1', type: 'function', function: { name: 'test_tool' } }]
          },
          {
            role: 'tool',
            tool_call_id: 'call_1',
            name: 'test_tool',
            content: '{"success": true}'
          }
        ]
      end

      it 'handles tool result with nil result field' do
        executed_tools = [
          {
            tool_name: 'test_tool',
            arguments: {},
            result: { success: true, result: nil }
          }
        ]

        result = flow_manager.send(:convert_tool_history_to_english, basic_messages, executed_tools)
        summary_msg = result.last
        expect(summary_msg[:content]).to eq('Actions completed: test_tool (completed)')
      end

      it 'handles tool result that is not a hash' do
        executed_tools = [
          {
            tool_name: 'test_tool',
            arguments: {},
            result: 'simple string result'
          }
        ]

        result = flow_manager.send(:convert_tool_history_to_english, basic_messages, executed_tools)
        summary_msg = result.last
        expect(summary_msg[:content]).to eq('Actions completed: test_tool (completed)')
      end

      it 'handles tool result with nested hash structure' do
        executed_tools = [
          {
            tool_name: 'test_tool',
            arguments: {},
            result: { success: true, result: 'Tool executed successfully' }
          }
        ]

        result = flow_manager.send(:convert_tool_history_to_english, basic_messages, executed_tools)
        summary_msg = result.last
        expect(summary_msg[:content]).to eq('Actions completed: test_tool (Tool executed successfully)')
      end

      it 'handles empty executed_tools array' do
        result = flow_manager.send(:convert_tool_history_to_english, basic_messages, [])

        # Should filter out tool messages but not add summary
        expect(result.none? { |msg| msg.key?(:tool_calls) }).to be true
        expect(result.none? { |msg| msg.key?(:tool_call_id) }).to be true
        expect(result.last[:role]).to eq('user')
        expect(result.last[:content]).to eq('Test')
      end
    end

    context 'with complex realistic production scenario' do
      let(:production_like_messages) do
        [
          {
            role: 'system',
            content: 'You are Buddy, the friendly AI companion for GlitchCube.'
          },
          {
            role: 'user',
            content: 'Turn all the lights to a warm yellow color and set them to medium brightness'
          },
          {
            role: 'assistant',
            content: 'I\'ll help you set the lights to a warm yellow color at medium brightness.',
            tool_calls: [
              {
                id: 'call_abc123',
                type: 'function',
                function: {
                  name: 'set_light_state',
                  arguments: '{"entity_id": "all", "color": "yellow", "brightness": 150}'
                }
              }
            ]
          },
          {
            role: 'tool',
            tool_call_id: 'call_abc123',
            name: 'set_light_state',
            content: '{"success": true, "message": "Successfully set all lights to yellow at brightness 150", "entities_affected": 5}'
          }
        ]
      end

      let(:production_executed_tools) do
        [
          {
            tool_name: 'set_light_state',
            arguments: { entity_id: 'all', color: 'yellow', brightness: 150 },
            result: {
              success: true,
              result: '✅ Set all 5 lights to yellow at brightness 150'
            }
          }
        ]
      end

      it 'correctly processes a realistic production scenario' do
        result = flow_manager.send(:convert_tool_history_to_english, production_like_messages, production_executed_tools)

        # Should have 3 messages: system, user, and summary
        expect(result.length).to eq(3)

        # Check system message is preserved
        expect(result[0][:role]).to eq('system')
        expect(result[0][:content]).to include('Buddy')

        # Check user message is preserved
        expect(result[1][:role]).to eq('user')
        expect(result[1][:content]).to include('warm yellow color')

        # Check summary is added correctly
        expect(result[2][:role]).to eq('user')
        expect(result[2][:content]).to eq('Actions completed: set_light_state (✅ Set all 5 lights to yellow at brightness 150)')

        # Verify problematic messages are filtered
        expect(result.none? { |msg| msg.key?(:tool_calls) }).to be true
        expect(result.none? { |msg| msg.key?(:tool_call_id) }).to be true
      end

      it 'prevents the specific 400 error by removing incompatible message formats' do
        # This is the key test - ensure Claude Sonnet 4 compatible format
        result = flow_manager.send(:convert_tool_history_to_english, production_like_messages, production_executed_tools)

        # Verify no message contains tool_calls or tool_call_id
        result.each do |message|
          expect(message).not_to have_key(:tool_calls)
          expect(message).not_to have_key(:tool_call_id)
          expect(message).to have_key(:role)
          expect(message).to have_key(:content)
        end

        # All messages should have valid roles for Claude
        valid_roles = ['system', 'user', 'assistant']
        result.each do |message|
          expect(valid_roles).to include(message[:role])
        end
      end
    end

    context 'with malformed or unusual message structures' do
      it 'handles messages with symbol keys' do
        messages = [
          { role: :user, content: 'Hello' },
          {
            role: :assistant,
            tool_calls: [{ id: 'call_1' }]
          }
        ]

        result = flow_manager.send(:convert_tool_history_to_english, messages, [])
        expect(result.length).to eq(1)
        expect(result[0][:role]).to eq(:user)
      end

      it 'handles messages with additional unexpected keys' do
        messages = [
          {
            role: 'user',
            content: 'Hello',
            extra_field: 'should be preserved',
            another_field: 123
          },
          {
            role: 'assistant',
            tool_calls: [{ id: 'call_1' }],
            some_metadata: 'should be filtered out with tool_calls'
          }
        ]

        result = flow_manager.send(:convert_tool_history_to_english, messages, [])
        expect(result.length).to eq(1)
        expect(result[0][:extra_field]).to eq('should be preserved')
        expect(result[0][:another_field]).to eq(123)
      end
    end
  end
end
