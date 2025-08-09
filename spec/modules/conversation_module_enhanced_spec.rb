# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/modules/conversation_module'

RSpec.describe ConversationModule, 'enhanced features' do
  let(:module_instance) { described_class.new }
  let(:mock_home_assistant) { instance_double(HomeAssistantClient) }
  let(:mock_llm_response) do
    instance_double(
      Services::LLMResponse,
      response_text: 'Hello from Glitch Cube!',
      continue_conversation?: true,
      has_tool_calls?: false,
      model: 'test-model',
      cost: 0.001,
      usage: { prompt_tokens: 10, completion_tokens: 20 }
    )
  end

  before do
    # Mock HomeAssistant client
    allow(HomeAssistantClient).to receive(:new).and_return(mock_home_assistant)
    allow(mock_home_assistant).to receive(:speak).and_return(true)

    # Mock LLM Service
    allow(Services::LLMService).to receive(:complete).and_return(mock_llm_response)

    # Mock conversation persistence
    mock_conversation = double(
      'Conversation',
      id: 'test-123',
      session_id: 'session-456',
      add_message: true,
      update_totals!: true
    )
    allow(Conversation).to receive_message_chain(:active, :find_by).and_return(nil)
    allow(Conversation).to receive(:create!).and_return(mock_conversation)

    # Mock services
    allow(Services::LoggerService).to receive(:log_interaction)
    allow(Services::LoggerService).to receive(:log_tts)

    # Mock system prompt
    mock_prompt_service = instance_double(Services::SystemPromptService)
    allow(Services::SystemPromptService).to receive(:new).and_return(mock_prompt_service)
    allow(mock_prompt_service).to receive(:generate).and_return('System prompt')

    # Mock HomeAssistantClient completely for integration tests
    allow(HomeAssistantClient).to receive(:new).and_return(mock_home_assistant)
    allow(mock_home_assistant).to receive_messages(
      call_service: true,
      state: 'Gallery Main Hall',
      battery_level: 85,
      temperature: 22.5,
      motion_detected?: false
    )
  end

  describe '#call with enhancements' do
    let(:message) { 'How is the temperature?' }
    let(:context) { { include_sensors: true, persona: 'contemplative' } }

    it 'integrates all enhancements in conversation flow', :vcr do
      # Mock conversation session to avoid database
      mock_session = instance_double(Services::ConversationSession,
                                     session_id: 'test-session',
                                     messages_for_llm: [],
                                     add_message: double('message', role: 'user', content: message),
                                     messages: double('messages', count: 0),
                                     created_at: Time.now - 1.minute,
                                     metadata: {})
      allow(Services::ConversationSession).to receive(:find_or_create).and_return(mock_session)

      # Mock successful LLM response
      allow(Services::LLMService).to receive(:complete_with_messages).and_return(mock_llm_response)

      # Expect sensor enrichment
      expect(mock_home_assistant).to receive(:battery_level).and_return(75)
      expect(mock_home_assistant).to receive(:temperature).and_return(23.0)
      expect(mock_home_assistant).to receive(:motion_detected?).and_return(true)

      result = module_instance.call(message: message, context: context)

      expect(result[:response]).to eq('Hello from Glitch Cube!')
      expect(result[:persona]).to eq('contemplative')
      expect(result[:continue_conversation]).to be true
    end

    it 'handles failures gracefully with error recovery', :vcr do
      # Mock conversation session to avoid database
      mock_session = instance_double(Services::ConversationSession,
                                     session_id: 'test-session',
                                     messages_for_llm: [],
                                     add_message: double('message', role: 'assistant', content: 'offline response'),
                                     messages: double('messages', count: 0),
                                     created_at: Time.now - 1.minute,
                                     metadata: {})
      allow(Services::ConversationSession).to receive(:find_or_create).and_return(mock_session)

      # Simulate LLM failure
      allow(Services::LLMService).to receive(:complete_with_messages).and_raise(Services::LLMService::LLMError, 'Temporary error')

      result = module_instance.call(message: message, context: context)

      expect(result[:response].downcase).to match(/offline|connectivity|unavailable|quiet|spirit|digital silence|presence|artistic moment|computational resources|reflecting/)
      expect(result[:error]).to eq('llm_error')
    end
  end
end
