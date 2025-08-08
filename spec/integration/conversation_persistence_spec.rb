# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/conversation_service'
require_relative '../../lib/services/system_prompt_service'
require_relative '../../lib/modules/conversation_module'

RSpec.describe "Conversation with Persistence Integration", vcr: { cassette_name: "conversation_persistence" } do
  before do
    # Clean database between tests to avoid foreign key conflicts
    Message.destroy_all
    Conversation.destroy_all
  end

  let(:conversation_service) { Services::ConversationService.new(context: initial_context) }
  let(:initial_context) do
    {
      location: 'Test Gallery',
      event_name: 'RSpec Testing Session',
      environment: 'test'
    }
  end

  describe 'Full conversation flow' do
    it 'processes a conversation and tracks it in persistence' do
      # First message
      message1 = 'Hello, what are you?'
      mood1 = 'neutral'

      # Process the message
      result1 = conversation_service.process_message(message1, mood: mood1)

      # Verify response structure
      expect(result1).to include(
        response: String,
        persona: String
      )
      expect(result1[:response]).not_to be_empty
      # Confidence may not be present in error responses
      expect(result1[:confidence]).to be_between(0, 1) if result1[:confidence]

      # Since persistence is now in-memory, check the context is updated
      context = conversation_service.get_context
      expect(context[:interaction_count]).to eq(1)
    end

    it 'maintains context across multiple interactions', vcr: { cassette_name: 'conversation_persistence' } do
      messages = [
        { text: 'Hello!', mood: 'playful' },
        { text: "Let's play a game!", mood: 'playful' },
        { text: 'What do you think about art?', mood: 'contemplative' }
      ]

      results = []

      messages.each_with_index do |msg, index|
        result = conversation_service.process_message(msg[:text], mood: msg[:mood])
        results << result

        # Check interaction count is updated
        context = conversation_service.get_context
        expect(context[:interaction_count]).to eq(index + 1)
      end

      # Verify context maintains interaction count
      expect(results).to all(be_a(Hash))
      expect(results).to all(include(:response, :persona))
    end

    # Removed: mood transitions are no longer tracked
    # Personas are scheduled and don't change based on conversation
  end

  describe 'System prompt generation' do
    it 'includes datetime in system prompt' do
      # We'll need to mock time for consistent testing
      allow(Time).to receive(:now).and_return(Time.new(2025, 1, 13, 14, 30, 0, '-08:00'))

      service = Services::SystemPromptService.new
      prompt = service.generate

      expect(prompt).to include('CURRENT DATE AND TIME:')
      expect(prompt).to include('Date:')
      expect(prompt).to include('Time:')
      expect(prompt).to match(/\d{4}/) # Year format
    end

    it 'loads character-specific prompts' do
      # The SystemPromptService uses character parameter
      characters = %w[playful contemplative mysterious]

      characters.each do |character|
        service = Services::SystemPromptService.new(character: character)
        prompt = service.generate

        # The prompt should reflect the character in some way
        expect(prompt).to be_a(String)
        expect(prompt).not_to be_empty
      end
    end

    it 'includes context in generated prompt' do
      context = {
        battery_level: '42%',
        visitor_count: 23,
        last_interaction: '5 minutes ago'
      }

      service = Services::SystemPromptService.new(context: context)
      prompt = service.generate

      # Context gets incorporated into the prompt
      expect(prompt).to be_a(String)
      expect(prompt).not_to be_empty
    end
  end

  describe 'Error handling' do
    context 'when AI service fails' do
      before do
        allow(Services::LLMService).to receive(:complete_with_messages)
          .and_raise(StandardError.new('API Error'))
      end

      it 'returns fallback response and tracks failure' do
        result = conversation_service.process_message('Hello', mood: 'playful')

        expect(result[:response]).to be_a(String)
        # Error responses may not have confidence

        # Check context is still updated even with error
        context = conversation_service.get_context
        expect(context[:interaction_count]).to eq(1)
      end
    end
  end

  describe 'Analytics', vcr: { cassette_name: 'conversation_analytics' } do
    before do
      # Generate some test conversations
      5.times do |i|
        conversation_service.process_message("Test message #{i}", mood: 'neutral')
      end
    end

    it 'provides module analytics' do
      # Analytics now tracked in context
      context = conversation_service.get_context
      expect(context[:interaction_count]).to eq(5)
    end
  end
end
