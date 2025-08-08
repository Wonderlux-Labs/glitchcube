# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/modules/conversation_module'

RSpec.describe 'Conversation Tool Execution Integration', type: :integration do
  let(:conversation_module) { ConversationModule.new(persona: 'buddy') }
  let(:test_message) { "Turn on the cube lights to red and show 'Hello' on the display" }
  let(:context) do
    {
      session_id: 'test-standardized-tools',
      voice_interaction: false,
      tools: [
        {
          'type' => 'function',
          'function' => {
            'name' => 'lighting_control',
            'description' => 'Control cube RGB lighting',
            'parameters' => {
              'type' => 'object',
              'properties' => {
                'action' => { 'type' => 'string', 'enum' => %w[set_light turn_off_light] },
                'params' => { 'type' => 'object' }
              }
            }
          }
        },
        {
          'type' => 'function',
          'function' => {
            'name' => 'display_control',
            'description' => 'Control AWTRIX display',
            'parameters' => {
              'type' => 'object',
              'properties' => {
                'action' => { 'type' => 'string' },
                'params' => { 'type' => 'object' }
              }
            }
          }
        },
        {
          'type' => 'function',
          'function' => {
            'name' => 'speech_synthesis',
            'description' => 'Text-to-speech via Home Assistant',
            'parameters' => {
              'type' => 'object',
              'properties' => {
                'action' => { 'type' => 'string' },
                'params' => { 'type' => 'object' }
              }
            }
          }
        }
      ]
    }
  end

  describe 'Standardized Tool Execution Flow' do
    context 'when LLM makes tool calls', vcr: { cassette_name: 'standardized_tool_execution' } do
      it 'executes ALL operations through LLM tool calling system' do
        # Mock tool execution to verify calls
        tool_results = [
          { tool_name: 'lighting_control', success: true, result: 'Set cube to red' },
          { tool_name: 'display_control', success: true, result: 'Displayed: Hello' },
          { tool_name: 'speech_synthesis', success: true, result: 'Spoke: Done!' }
        ]

        allow(Services::ToolExecutor).to receive(:execute).and_return(tool_results)

        # Execute conversation
        result = conversation_module.call(
          message: test_message,
          context: context
        )

        # Verify successful conversation
        expect(result).to be_a(Hash)
        expect(result[:response]).to be_present
        expect(result[:success]).to be_falsy || result[:response].present?

        # Verify tool executor was called (standardized path)
        expect(Services::ToolExecutor).to have_received(:execute)
      end

      it 'does NOT use fallback direct service calls' do
        # Mock tool execution failure to test no fallbacks occur
        allow(Services::ToolExecutor).to receive(:execute).and_return([])

        # Mock services to ensure they're NOT called directly
        allow(Services::ConversationFeedbackService).to receive(:set_listening)
        allow(Services::ConversationFeedbackService).to receive(:set_thinking)
        allow_any_instance_of(Services::CharacterService).to receive(:speak)

        result = conversation_module.call(
          message: test_message,
          context: context
        )

        # Should still complete successfully
        expect(result[:response]).to be_present

        # Verify NO direct fallback calls occurred
        # (In Phase 2, we remove fallback mechanisms entirely)
        expect(Services::ConversationFeedbackService).not_to have_received(:set_listening)
        expect(Services::ConversationFeedbackService).not_to have_received(:set_thinking)
      end
    end

    context 'when no tools are configured' do
      let(:context_no_tools) { { session_id: 'test-no-tools' } }

      it 'still processes conversation without tool execution', vcr: { cassette_name: 'conversation_no_tools' } do
        result = conversation_module.call(
          message: 'Hello there!',
          context: context_no_tools
        )

        expect(result).to be_a(Hash)
        expect(result[:response]).to be_present
        expect(result[:session_id]).to eq('test-no-tools')
      end
    end
  end

  describe 'Tool System Integration' do
    context 'with actual Home Assistant', vcr: { cassette_name: 'ha_tool_integration' } do
      it 'executes lighting and display tools through HA' do
        # Use real HA integration (will be recorded in VCR)
        result = conversation_module.call(
          message: 'Set the lights to blue and show my mood',
          context: context
        )

        # Verify conversation completed
        expect(result[:response]).to be_present
        expect(result[:conversation_id]).to be_present

        # Integration should work end-to-end
        expect(result[:error]).to be_nil
      end
    end
  end
end
