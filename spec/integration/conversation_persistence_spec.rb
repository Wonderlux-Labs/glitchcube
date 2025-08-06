# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/conversation_service'
require_relative '../../lib/modules/conversation_module'

RSpec.describe 'Conversation with Persistence Integration', :database, :vcr do
  before(:all) do
    skip('Skipping database persistence specs: DATABASE_URL is not set to Postgres') unless ENV['DATABASE_URL']&.start_with?('postgres')
  end

  let(:conversation_service) { Services::ConversationService.new(context: initial_context) }
  let(:initial_context) do
    {
      location: 'Test Gallery',
      event_name: 'RSpec Testing Session',
      environment: 'test'
    }
  end

  before do
    # Persistence removed with Desiru framework
    skip 'Persistence functionality removed - using in-memory conversation storage now'
  end

  describe 'Full conversation flow' do
    xit 'processes a conversation and tracks it in persistence' do
      # First message
      message1 = 'Hello, what are you?'
      mood1 = 'neutral'

      # Process the message
      result1 = conversation_service.process_message(message1, mood: mood1)

      # Verify response structure
      expect(result1).to include(
        response: String,
        suggested_mood: String,
        confidence: Numeric
      )
      expect(result1[:response]).not_to be_empty
      expect(result1[:confidence]).to be_between(0, 1)

      # Check persistence was called
      history = GlitchCube::Persistence.get_conversation_history(limit: 1)
      expect(history).not_to be_empty

      last_conversation = history.first
      expect(last_conversation[:module]).to eq('ConversationModule')
      expect(last_conversation[:input]).to include(
        message: message1,
        mood: mood1
      )
      expect(last_conversation[:output]).to eq(result1)
      expect(last_conversation[:success]).to be true
    end

    xit 'maintains context across multiple interactions', vcr: { cassette_name: 'conversation_persistence' } do
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

      # Verify all conversations were tracked
      history = GlitchCube::Persistence.get_conversation_history(limit: 3)
      expect(history.length).to eq(3)

      # Verify conversations are in reverse chronological order
      expect(history[0][:input][:message]).to eq('What do you think about art?')
      expect(history[1][:input][:message]).to eq("Let's play a game!")
      expect(history[2][:input][:message]).to eq('Hello!')
    end

    xit 'tracks mood transitions' do
      # Start with playful
      conversation_service.process_message("Let's have fun!", mood: 'playful')

      # Transition to contemplative
      result2 = conversation_service.process_message(
        "But I've been thinking deeply about existence...",
        mood: 'contemplative'
      )

      # Check context tracks mood change
      context = conversation_service.get_context
      if result2[:suggested_mood] != 'playful'
        expect(context[:mood_changed]).to be true
        expect(context[:previous_mood]).to eq('playful')
      end
    end
  end

  describe 'System prompt generation' do
    it 'includes datetime in system prompt' do
      # We'll need to mock time for consistent testing
      allow(Time).to receive(:now).and_return(Time.new(2025, 1, 13, 14, 30, 0, '-08:00'))

      service = Services::SystemPromptService.new
      prompt = service.generate

      expect(prompt).to include('CURRENT DATE AND TIME:')
      expect(prompt).to include('Date: Monday, January 13, 2025')
      expect(prompt).to include('Time: 02:30 PM')
    end

    it 'loads character-specific prompts' do
      moods = %w[playful contemplative mysterious]

      moods.each do |mood|
        service = Services::SystemPromptService.new(character: mood)
        prompt = service.generate

        case mood
        when 'playful'
          expect(prompt).to include('PLAYFUL mode')
          expect(prompt).to include('bubbling with creative energy')
        when 'contemplative'
          expect(prompt).to include('CONTEMPLATIVE mode')
          expect(prompt).to include('philosophical wonder')
        when 'mysterious'
          expect(prompt).to include('MYSTERIOUS mode')
          expect(prompt).to include('enigmatic presence')
        end
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

      expect(prompt).to include('ADDITIONAL CONTEXT:')
      expect(prompt).to include('Battery Level: 42%')
      expect(prompt).to include('Visitor Count: 23')
      expect(prompt).to include('Last Interaction: 5 minutes ago')
    end
  end

  describe 'Error handling' do
    context 'when AI service fails' do
      before do
        allow(Services::LLMService).to receive(:complete)
          .and_raise(StandardError.new('API Error'))
      end

      xit 'returns fallback response and tracks failure' do
        # Skip this test - tracking failures requires updating the conversation module
        # to track even when there's an error, which is a future enhancement
        result = conversation_service.process_message('Hello', mood: 'playful')

        expect(result[:response]).to be_a(String)
        expect(result[:confidence]).to eq(0.5)

        # Should still track the conversation even with error
        history = GlitchCube::Persistence.get_conversation_history(limit: 1)
        expect(history).not_to be_empty
      end
    end
  end

  describe 'Analytics' do
    before do
      # Generate some test conversations
      5.times do |i|
        conversation_service.process_message("Test message #{i}", mood: 'neutral')
      end
    end

    xit 'provides module analytics' do
      analytics = GlitchCube::Persistence.get_module_analytics('ConversationModule')

      expect(analytics).to include(
        total_executions: Integer,
        success_rate: Numeric,
        avg_response_time: Numeric,
        recent_errors: Array
      )

      expect(analytics[:total_executions]).to be >= 5
      expect(analytics[:success_rate]).to be_between(0, 100)
    end
  end
end
