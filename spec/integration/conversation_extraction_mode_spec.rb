# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Conversation Extraction Mode', type: :integration do
  include_context 'with_full_conversation_setup'

  let(:session_id) { 'test-session-extraction' }
  let(:persona) { 'buddy' }
  let(:message) { 'Can you make the lights blue and play some music?' }

  before do
    # Force conversation extraction mode for this test
    allow(GlitchCube.config).to receive(:tool_execution_mode).and_return(:conversation_extraction)
  end

  describe 'conversation flow with action extraction and Claude execution' do
    it 'processes conversation without tool calling and executes actions via Claude' do
      # Mock the LLM response to include actions in JSON format
      mock_llm_response = instance_double(
        Services::Llm::LLMResponse,
        response_text: "I'd love to help you set the perfect mood! Let me take care of that lighting and music.",
        parsed_content: {
          'response' => "I'd love to help you set the perfect mood! Let me take care of that lighting and music.",
          'actions' => ['Turn lights blue', 'Play ambient music'],
          'continue_conversation' => true
        },
        model: 'anthropic/claude-sonnet-4',
        usage: { prompt_tokens: 150, completion_tokens: 80 },
        cost: 0.05,
        tool_calls?: false,
        tool_calls: []
      )

      allow(Services::Llm::LLMService).to receive(:complete_with_messages).and_return(mock_llm_response)

      # Mock the Home Assistant client call to Claude
      mock_ha_client = instance_double(Services::Core::HomeAssistantClient)
      allow(Services::Core::HomeAssistantClient).to receive(:new).and_return(mock_ha_client)

      # Mock Claude's response via Home Assistant
      claude_response = {
        'response' => {
          'speech' => {
            'plain' => {
              'speech' => 'I have successfully turned the lights blue and started playing ambient music for you.'
            }
          }
        }
      }

      allow(mock_ha_client).to receive(:process_voice_command).and_return(claude_response)

      result = conversation_module.call(
        message: message,
        context: { session_id: session_id },
        persona: persona
      )

      # Verify the conversation succeeded with proper response structure
      expect(result[:response]).to eq("I'd love to help you set the perfect mood! Let me take care of that lighting and music.")
      expect(result[:session_id]).to eq(session_id)
      expect(result[:persona]).to eq(persona)
      expect(result[:error]).to be_nil

      # Verify no actual tool calling happened (conversation extraction mode)
      expect(Services::Llm::LLMService).to have_received(:complete_with_messages) do |args|
        expect(args[:tools]).to be_nil
        expect(args[:tool_choice]).to be_nil
      end

      # Verify Claude was called to execute actions
      expect(mock_ha_client).to have_received(:process_voice_command).with(
        include('Turn lights blue'),
        hash_including(agent_id: 'conversation.claude_conversation')
      )
    end

    it 'logs the complete action extraction and Claude execution process' do
      # Mock the LLM response
      mock_llm_response = instance_double(
        Services::Llm::LLMResponse,
        response_text: "Perfect! I'll set that up for you.",
        parsed_content: {
          'response' => "Perfect! I'll set that up for you.",
          'actions' => ['Turn lights to party mode'],
          'continue_conversation' => true
        },
        model: 'anthropic/claude-sonnet-4',
        usage: { prompt_tokens: 100, completion_tokens: 50 },
        cost: 0.03,
        tool_calls?: false,
        tool_calls: []
      )

      allow(Services::Llm::LLMService).to receive(:complete_with_messages).and_return(mock_llm_response)

      # Mock the Home Assistant client
      mock_ha_client = instance_double(Services::Core::HomeAssistantClient)
      allow(Services::Core::HomeAssistantClient).to receive(:new).and_return(mock_ha_client)
      allow(mock_ha_client).to receive(:process_voice_command).and_return({
                                                                            'response' => { 'text' => 'Party mode activated!' }
                                                                          })

      conversation_module.call(
        message: 'Turn on party mode',
        context: { session_id: session_id },
        persona: persona
      )

      # Verify Claude was called with the correct format
      expect(mock_ha_client).to have_received(:process_voice_command).with(
        include('1. Turn lights to party mode'),
        hash_including(
          agent_id: 'conversation.claude_conversation',
          conversation_id: session_id
        )
      )
    end
  end

  private

  def conversation_module
    @conversation_module ||= Modules::ConversationModule.new
  end
end
