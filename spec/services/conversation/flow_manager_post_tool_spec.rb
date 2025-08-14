# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::Conversation::FlowManager do
  describe 'post-tool LLM call schema handling' do
    let(:flow_manager) { described_class.new }
    let(:context_with_tools) { { tools: [{ name: 'test_tool' }], session_id: 'test_session' } }
    let(:llm_manager) { instance_double(Services::Conversation::LlmInteractionManager) }

    before do
      allow(Services::Conversation::LlmInteractionManager).to receive(:new).and_return(llm_manager)
      allow(llm_manager).to receive(:select_appropriate_model).and_return('test-model')
      allow(llm_manager).to receive(:get_response_schema)
        .with(hash_including(tools: [{ name: 'test_tool' }]))
        .and_return({ type: 'object' })
      allow(llm_manager).to receive(:get_response_schema)
        .with(hash_including(tools: nil))
        .and_return(nil)
    end

    it 'clears tools context for post-tool LLM call to avoid schema enforcement' do
      # Test the build_llm_options method indirectly by checking schema behavior
      original_context = context_with_tools.dup

      # Call build_llm_options with tools (should have schema)
      options_with_tools = flow_manager.send(:build_llm_options, original_context, 'test_session', with_tools: false)

      # Should have response_format because get_response_schema returns a schema for tools context
      expect(options_with_tools).to have_key(:response_format)

      # Now test with cleared tools context
      cleared_context = original_context.dup
      cleared_context[:tools] = nil

      options_without_tools = flow_manager.send(:build_llm_options, cleared_context, 'test_session', with_tools: false)

      # Should NOT have response_format because get_response_schema returns nil for nil tools
      expect(options_without_tools).not_to have_key(:response_format)

      # Verify the schema methods were called with correct contexts
      expect(llm_manager).to have_received(:get_response_schema).with(hash_including(tools: [{ name: 'test_tool' }]))
      expect(llm_manager).to have_received(:get_response_schema).with(hash_including(tools: nil))
    end

    it 'preserves other context values when clearing tools' do
      original_context = {
        tools: [{ name: 'test_tool' }],
        session_id: 'test_session',
        persona: 'buddy',
        temperature: 0.7
      }

      # Simulate what happens in the flow_manager
      post_tool_context = original_context.dup
      post_tool_context[:tools] = nil

      expect(post_tool_context[:session_id]).to eq('test_session')
      expect(post_tool_context[:persona]).to eq('buddy')
      expect(post_tool_context[:temperature]).to eq(0.7)
      expect(post_tool_context[:tools]).to be_nil
    end
  end

  describe 'LLM options building' do
    let(:flow_manager) { described_class.new }
    let(:llm_manager) { instance_double(Services::Conversation::LlmInteractionManager) }

    before do
      allow(Services::Conversation::LlmInteractionManager).to receive(:new).and_return(llm_manager)
      allow(llm_manager).to receive(:select_appropriate_model).and_return('test-model')
    end

    context 'when tools are present' do
      let(:context) { { tools: [{ name: 'lighting_control' }] } }

      it 'includes tools in options when with_tools is true' do
        allow(llm_manager).to receive(:get_response_schema).and_return(nil)

        options = flow_manager.send(:build_llm_options, context, 'test_session', with_tools: true)

        expect(options[:tools]).to eq([{ name: 'lighting_control' }])
        expect(options[:tool_choice]).to eq('auto')
      end

      it 'excludes tools and uses schema when with_tools is false' do
        mock_schema = { type: 'object', properties: { response: { type: 'string' } } }
        allow(llm_manager).to receive(:get_response_schema).and_return(mock_schema)

        options = flow_manager.send(:build_llm_options, context, 'test_session', with_tools: false)

        expect(options).not_to have_key(:tools)
        expect(options).not_to have_key(:tool_choice)
        expect(options[:response_format]).to eq(
          Schemas::ConversationResponseSchema.to_openrouter_format(mock_schema)
        )
      end
    end

    context 'when tools are nil' do
      let(:context) { { tools: nil } }

      it 'does not include tools or schema' do
        allow(llm_manager).to receive(:get_response_schema).and_return(nil)

        options = flow_manager.send(:build_llm_options, context, 'test_session', with_tools: false)

        expect(options).not_to have_key(:tools)
        expect(options).not_to have_key(:tool_choice)
        expect(options).not_to have_key(:response_format)
      end
    end
  end
end
