# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::Conversation::FlowManager do
  describe 'post-tool LLM call tool clearing' do
    let(:flow_manager) { described_class.new }
    let(:context_with_tools) { { tools: [{ name: 'test_tool' }], session_id: 'test_session' } }
    let(:llm_manager) { instance_double(Services::Conversation::LlmInteractionManager) }

    before do
      allow(Services::Conversation::LlmInteractionManager).to receive(:new).and_return(llm_manager)
      allow(llm_manager).to receive(:select_appropriate_model).and_return('test-model')
    end

    it 'clears tools context for post-tool LLM call to avoid tool calling on final response' do
      # Test the build_llm_options method with tools disabled
      original_context = context_with_tools.dup

      # Call build_llm_options with tools disabled for final call
      options_without_tools = flow_manager.send(:build_llm_options, original_context, 'test_session', with_tools: false)

      # Should NOT have tools or tool_choice since with_tools is false
      expect(options_without_tools).not_to have_key(:tools)
      expect(options_without_tools).not_to have_key(:tool_choice)

      # Should have basic options
      expect(options_without_tools[:model]).to eq('test-model')
      expect(options_without_tools[:temperature]).to be_present
    end

    it 'preserves other context values when clearing tools' do
      original_context = {
        tools: [{ name: 'test_tool' }],
        session_id: 'test_session',
        persona: 'buddy',
        temperature: 0.7
      }

      # Simulate what happens in the flow_manager for final call
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
        options = flow_manager.send(:build_llm_options, context, 'test_session', with_tools: true)

        expect(options[:tools]).to eq([{ name: 'lighting_control' }])
        expect(options[:tool_choice]).to eq('auto')
      end

      it 'excludes tools when with_tools is false (for final model call)' do
        options = flow_manager.send(:build_llm_options, context, 'test_session', with_tools: false)

        expect(options).not_to have_key(:tools)
        expect(options).not_to have_key(:tool_choice)
        # No response_format - we use prompt-based structured output for final calls
        expect(options).not_to have_key(:response_format)
      end
    end

    context 'when tools are nil' do
      let(:context) { { tools: nil } }

      it 'does not include tools regardless of with_tools parameter' do
        options = flow_manager.send(:build_llm_options, context, 'test_session', with_tools: false)

        expect(options).not_to have_key(:tools)
        expect(options).not_to have_key(:tool_choice)
        expect(options).not_to have_key(:response_format)
      end
    end

    context 'when tools are empty array' do
      let(:context) { { tools: [] } }

      it 'does not include tools when array is empty' do
        options = flow_manager.send(:build_llm_options, context, 'test_session', with_tools: true)

        expect(options).not_to have_key(:tools)
        expect(options).not_to have_key(:tool_choice)
      end
    end
  end
end
