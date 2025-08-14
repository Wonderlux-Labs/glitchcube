# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Tool Calling Pattern Bifurcation Integration' do
  include_context 'with_full_conversation_setup'

  let(:session_id) { 'integration-test-session' }
  let(:message) { 'Turn on the living room lights' }
  let(:context) do
    {
      session_id: session_id,
      tools: [
        {
          type: 'function',
          function: {
            name: 'turn_on_light',
            description: 'Turn on a light',
            parameters: {
              type: 'object',
              properties: {
                entity_id: { type: 'string', description: 'Light entity ID' }
              },
              required: %w[entity_id]
            }
          }
        }
      ]
    }
  end

  # Mock an LLM response that includes tool calls
  let(:mock_llm_response_with_tools) do
    OpenStruct.new(
      tool_calls?: true,
      tool_calls: [{ id: 'call_123', function: { name: 'turn_on_light', arguments: '{"entity_id": "light.living_room"}' } }],
      function_calls: [{ name: 'turn_on_light', arguments: { entity_id: 'light.living_room' } }],
      function_arguments_for: proc { |name| name == 'turn_on_light' ? { entity_id: 'light.living_room' } : nil },
      message_data: { role: 'assistant', content: 'I will turn on the living room lights.' },
      model: 'test-model',
      usage: { prompt_tokens: 100, completion_tokens: 50 },
      cost: 0.01
    )
  end

  let(:flow_manager) { Services::Conversation::FlowManager.new }

  before do
    # Mock the LLM interaction manager to return our mock response
    allow_any_instance_of(Services::Conversation::LlmInteractionManager)
      .to receive(:call_llm).and_return(mock_llm_response_with_tools)

    # Mock the ToolExecutor for default pattern
    allow(Services::ToolExecutor).to receive(:execute).and_return([
                                                                    { success: true, message: 'Light turned on successfully' }
                                                                  ])

    # Allow the conversation flow manager to work
    allow(Services::Logging::SimpleLogger).to receive(:info)
    allow(Services::Logging::SimpleLogger).to receive(:debug)
    allow(Services::Logging::SimpleLogger).to receive(:log_error)
  end

  describe 'default tool calling pattern' do
    before do
      allow(GlitchCube.config).to receive(:tool_calling_pattern).and_return(:default)
    end

    it 'processes tool calls through the traditional ToolExecutor' do
      result = flow_manager.process_conversation(message: message, context: context)

      expect(result).to be_a(Hash)
      expect(result[:response]).to be_present
      expect(result[:session_id]).to eq(session_id)

      # Verify the default tool execution path was used
      expect(Services::Logging::SimpleLogger).to have_received(:debug)
        .with('Using default tool execution pattern', any_args)
    end
  end

  describe 'back_to_hass tool calling pattern' do
    before do
      allow(GlitchCube.config).to receive(:tool_calling_pattern).and_return(:back_to_hass)

      # Mock the HomeAssistantToolProxy to return successful results
      allow_any_instance_of(Services::Conversation::HomeAssistantToolProxy)
        .to receive(:execute_via_hass).and_return({
                                                    tool_results: [
                                                      {
                                                        tool_call_id: 'call_123',
                                                        role: 'tool',
                                                        name: 'turn_on_light',
                                                        content: '{"success": true, "message": "Light turned on via Home Assistant"}'
                                                      }
                                                    ],
                                                    last_tool_calls: [
                                                      {
                                                        tool_name: 'turn_on_light',
                                                        arguments: { entity_id: 'light.living_room' },
                                                        result: { success: true, message: 'Light turned on via Home Assistant' }
                                                      }
                                                    ],
                                                    failed_tool_calls: []
                                                  })
    end

    it 'processes tool calls through the Home Assistant proxy' do
      result = flow_manager.process_conversation(message: message, context: context)

      expect(result).to be_a(Hash)
      expect(result[:response]).to be_present
      expect(result[:session_id]).to eq(session_id)

      # Verify the Home Assistant proxy path was used
      expect(Services::Logging::SimpleLogger).to have_received(:info)
        .with('Using Home Assistant tool proxy for execution', any_args)

      # Verify the tool calling pattern was logged
      expect(Services::Logging::SimpleLogger).to have_received(:info)
        .with('Starting tool execution cycle', hash_including(pattern: :back_to_hass))
    end

    it 'uses HomeAssistantToolProxy instead of default ToolExecutor' do
      expect_any_instance_of(Services::Conversation::HomeAssistantToolProxy)
        .to receive(:execute_via_hass)
        .with(mock_llm_response_with_tools, session_id)

      expect(Services::ToolExecutor).not_to receive(:execute)

      flow_manager.process_conversation(message: message, context: context)
    end
  end

  describe 'pattern switching' do
    it 'can switch between patterns without restart' do
      # Test default pattern first
      allow(GlitchCube.config).to receive(:tool_calling_pattern).and_return(:default)

      result1 = flow_manager.process_conversation(message: message, context: context)
      expect(result1[:response]).to be_present

      # Now test back_to_hass pattern
      allow(GlitchCube.config).to receive(:tool_calling_pattern).and_return(:back_to_hass)
      allow_any_instance_of(Services::Conversation::HomeAssistantToolProxy)
        .to receive(:execute_via_hass).and_return({
                                                    tool_results: [{ tool_call_id: 'call_123', role: 'tool', name: 'turn_on_light', content: '{"success": true}' }],
                                                    last_tool_calls: [],
                                                    failed_tool_calls: []
                                                  })

      result2 = flow_manager.process_conversation(message: message, context: context)
      expect(result2[:response]).to be_present

      # Both should succeed but use different execution paths
      expect(Services::Logging::SimpleLogger).to have_received(:debug)
        .with('Using default tool execution pattern', any_args)
      expect(Services::Logging::SimpleLogger).to have_received(:info)
        .with('Using Home Assistant tool proxy for execution', any_args)
    end
  end
end
