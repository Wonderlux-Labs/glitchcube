# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/conversation_service'
require_relative '../../lib/modules/conversation_module'

RSpec.describe Services::ConversationService do
  let(:initial_context) do
    {
      location: 'Test Gallery',
      event_name: 'RSpec Test'
    }
  end
  let(:service) { described_class.new(context: initial_context) }

  describe '#initialize' do
    it 'initializes with provided context' do
      expect(service.get_context).to include(initial_context)
    end

    it 'creates conversation module instance' do
      expect(service.conversation_module).to be_a(ConversationModule)
    end
  end

  describe '#process_message' do
    let(:message) { 'Hello, Glitch Cube!' }
    let(:mood) { 'playful' }

    context 'with successful response' do
      let(:mock_response) do
        {
          response: "Hello! I'm buzzing with excitement to meet you!",
          confidence: 0.95
        }
      end

      before do
        allow(service.conversation_module).to receive(:call).and_return(mock_response)
      end

      it 'calls conversation module with correct parameters' do
        expect(service.conversation_module).to receive(:call).with(
          message: message,
          context: hash_including(initial_context),
          persona: mood
        )

        service.process_message(message, mood: mood)
      end

      it 'increments interaction count' do
        service.process_message(message, mood: mood)
        expect(service.get_context[:interaction_count]).to eq(1)

        service.process_message(message, mood: mood)
        expect(service.get_context[:interaction_count]).to eq(2)
      end

      it 'returns the response from conversation module' do
        result = service.process_message(message, mood: mood)
        expect(result).to eq(mock_response)
      end
    end

    # Mood changes are no longer tracked - personas are scheduled
    # These tests are removed as we now have fixed personas that change on schedule
  end

  describe '#add_context' do
    it 'adds new context values' do
      service.add_context(:battery_level, '75%')
      service.add_context(:visitor_name, 'Alice')

      context = service.get_context
      expect(context[:battery_level]).to eq('75%')
      expect(context[:visitor_name]).to eq('Alice')
    end

    it 'overwrites existing context values' do
      service.add_context(:location, 'Gallery North')

      expect(service.get_context[:location]).to eq('Gallery North')
    end
  end

  describe '#reset_context' do
    let(:mock_response) do
      {
        response: 'Hello! Test response',
        confidence: 0.95
      }
    end

    before do
      # Add mock to avoid leaking between tests
      allow(service.conversation_module).to receive(:call).and_return(mock_response)
      service.process_message('Hello', mood: 'playful')
      service.add_context(:custom_field, 'value')
    end

    it 'resets context to initial state' do
      service.reset_context

      context = service.get_context
      expect(context[:interaction_count]).to eq(0)
      expect(context[:custom_field]).to be_nil
      expect(context[:session_id]).to be_a(String)
      expect(context[:started_at]).to be_a(Time)
    end

    it 'generates new session_id' do
      old_session_id = service.get_context[:session_id]
      service.reset_context
      new_session_id = service.get_context[:session_id]

      expect(new_session_id).not_to eq(old_session_id)
    end
  end

  describe '#get_context' do
    it 'returns a copy of context' do
      context = service.get_context
      context[:modified] = true

      expect(service.get_context[:modified]).to be_nil
    end
  end

  describe 'integration with system prompt' do
    it 'passes context through to system prompt generation', vcr: { cassette_name: 'services/conversation_service/system_prompt_integration' } do
      # Set up expected context values
      service.add_context(:location, 'Test Gallery')
      service.add_context(:event_name, 'RSpec Test')

      # Mock the LLM service to avoid real API calls
      mock_llm_response = double('LLMResponse',
                                 response_text: 'Hello! Test response',
                                 continue_conversation?: true,
                                 has_tool_calls?: false,
                                 parsed_content: { 'response' => 'Hello! Test response', 'continue_conversation' => true },
                                 cost: 0.001,
                                 model: 'google/gemini-2.5-flash',
                                 usage: { prompt_tokens: 100, completion_tokens: 50 })

      # Mock database operations to avoid foreign key issues
      mock_messages = double('Messages', count: 1)
      mock_session = double('ConversationSession')
      allow(mock_session).to receive(:add_message)
      allow(mock_session).to receive(:messages).and_return(mock_messages)
      allow(mock_session).to receive(:created_at).and_return(Time.now - 1.minute)
      allow(mock_session).to receive_messages(messages_for_llm: [], session_id: 'test-session-123')
      allow(Services::ConversationSession).to receive(:find_or_create).and_return(mock_session)

      # Mock LLM service to avoid real HTTP calls
      allow(Services::LLMService).to receive(:complete_with_messages).and_return(mock_llm_response)

      # Spy on SystemPromptService to verify it's called with correct parameters
      allow(Services::SystemPromptService).to receive(:new).and_call_original

      service.process_message('Hello', mood: 'playful')

      expect(Services::SystemPromptService).to have_received(:new).with(
        character: 'playful',
        context: hash_including(
          location: 'Test Gallery',
          event_name: 'RSpec Test',
          current_persona: 'playful',
          interaction_count: 1
        )
      )
    end
  end
end
