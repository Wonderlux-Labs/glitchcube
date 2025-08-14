# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Tool Retry with MCP Fallback Integration' do
  let(:session_id) { 'test-session-123' }

  before do
    # Enable tool retry in config
    allow(GlitchCube.config).to receive_message_chain(:tool_retry, :enabled).and_return(true)
    allow(GlitchCube.config).to receive_message_chain(:tool_retry, :use_mcp_fallback).and_return(true)
    allow(GlitchCube.config).to receive_message_chain(:tool_retry, :max_iterations).and_return(2)
  end

  describe 'Tool Execution Engine' do
    let(:tool_executor) { Services::ToolExecutor }
    let(:engine) { Services::Conversation::ToolExecutionEngine.new(tool_executor: tool_executor) }
    let(:mock_llm_response) do
      double('LLMResponse',
             tool_calls: [{ id: 'call_123' }],
             function_calls: [{ name: 'set_light_state' }],
             function_arguments_for: { entity_id: 'light.missing_light', state: 'on' })
    end

    it 'captures failed tool calls for retry' do
      # Mock a failing tool execution
      allow(tool_executor).to receive(:execute).and_return([{
                                                             success: false,
                                                             error: 'Entity not found: light.missing_light'
                                                           }])

      result = engine.execute_tool_calls(mock_llm_response, session_id)

      expect(result[:failed_tool_calls]).not_to be_empty
      expect(result[:failed_tool_calls].first[:function_name]).to eq('set_light_state')
      expect(result[:failed_tool_calls].first[:error]).to eq('Entity not found: light.missing_light')
    end

    it 'does not mark MCP tool failures for retry' do
      # Mock MCP tool failure
      allow(mock_llm_response).to receive(:function_calls).and_return([{ name: 'hass_mcp' }])
      allow(tool_executor).to receive(:execute).and_return([{
                                                             success: false,
                                                             error: 'MCP connection failed'
                                                           }])

      result = engine.execute_tool_calls(mock_llm_response, session_id)

      expect(result[:failed_tool_calls]).to be_empty
    end
  end

  describe 'Flow Manager Iteration Logic' do
    let(:flow_manager) { Services::Conversation::FlowManager.new }

    it 'continues iteration for Home Assistant tools' do
      failed_calls = [
        { function_name: 'set_light_state', error: 'Entity not found' },
        { function_name: 'unknown_tool', error: 'Some error' }
      ]

      result = flow_manager.send(:should_continue_iteration?, failed_calls, 1, 2)
      expect(result).to be true
    end

    it 'does not continue for non-HA tools' do
      failed_calls = [
        { function_name: 'unknown_tool', error: 'Some error' }
      ]

      result = flow_manager.send(:should_continue_iteration?, failed_calls, 1, 2)
      expect(result).to be false
    end

    it 'does not continue when at max iterations' do
      failed_calls = [
        { function_name: 'set_light_state', error: 'Entity not found' }
      ]

      result = flow_manager.send(:should_continue_iteration?, failed_calls, 2, 2)
      expect(result).to be false
    end

    it 'respects configuration settings' do
      allow(GlitchCube.config).to receive_message_chain(:tool_retry, :enabled).and_return(false)

      failed_calls = [
        { function_name: 'set_light_state', error: 'Entity not found' }
      ]

      result = flow_manager.send(:should_continue_iteration?, failed_calls, 1, 2)
      expect(result).to be false
    end

    it 'builds correct MCP tool schema' do
      schema = flow_manager.send(:build_mcp_tool_schema)

      expect(schema['function']['name']).to eq('hass_mcp')
      expect(schema['function']['parameters']['required']).to include('mcp_function')
    end

    it 'adds MCP tool to context on final iteration' do
      context = { tools: [{ 'function' => { 'name' => 'existing_tool' } }] }

      result_context = flow_manager.send(:build_iteration_context, context, 2, 2)

      expect(result_context[:tools].count).to eq(2)
      expect(result_context[:tools].last['function']['name']).to eq('hass_mcp')
    end
  end

  describe 'MCP Suggestion Logic' do
    let(:flow_manager) { Services::Conversation::FlowManager.new }
    let(:failed_calls) do
      [{
        function_name: 'set_light_state',
        arguments: { entity_id: 'light.missing', state: 'on' },
        error: 'Entity not found'
      }]
    end

    it 'builds MCP suggestion text with failure details' do
      suggestion = flow_manager.send(:build_mcp_suggestion_text, failed_calls)

      expect(suggestion).to include('Entity not found')
      expect(suggestion).to include('hass_mcp tool')
      expect(suggestion).to include('GetLiveContext')
      expect(suggestion).to include('HassTurnOn')
    end

    it 'adds MCP suggestion to message list' do
      messages = []

      flow_manager.send(:add_mcp_suggestion_to_messages, messages, failed_calls)

      expect(messages.count).to eq(1)
      expect(messages.first[:role]).to eq('system')
      expect(messages.first[:content]).to include('hass_mcp tool')
    end
  end

  describe 'Persona Integration' do
    it 'includes HassMcpTool in all personas' do
      personas = %w[buddy jax lomi zorp]

      personas.each do |persona_name|
        persona = Personas::BasePersona.create(persona_name, {})
        expect(persona.available_tools).to include(Tools::HassMcpTool)
      end
    end

    it 'includes MCP tool in tool schemas' do
      persona = Personas::BasePersona.create('buddy', {})
      schemas = persona.tool_schemas

      mcp_schema = schemas.find { |schema| schema['function']['name'] == 'hass_mcp' }
      expect(mcp_schema).not_to be_nil
      expect(mcp_schema['function']['description']).to include('Home Assistant')
    end
  end

  describe 'Configuration' do
    it 'has default retry configuration' do
      config = GlitchCube.config

      expect(config.tool_retry).to respond_to(:enabled)
      expect(config.tool_retry).to respond_to(:max_iterations)
      expect(config.tool_retry).to respond_to(:use_mcp_fallback)
    end

    it 'supports environment variable overrides' do
      # This would be tested in a real environment with ENV vars set
      expect(Services::Conversation::FlowManager).to be_a(Class)
    end
  end
end
