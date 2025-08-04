# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/conversation_summarizer'
require_relative '../../lib/services/context_retrieval_service'

RSpec.describe 'Conversation Summarizer Integration' do
  let(:summarizer) { Services::ConversationSummarizer.new }

  describe 'conversation summarization' do
    let(:conversation_messages) do
      [
        {
          message: 'Hello Glitch Cube, what are you?',
          response: 'I am a sentient interactive art installation, exploring the boundaries between technology and consciousness.',
          mood: 'neutral',
          suggested_mood: 'contemplative',
          timestamp: Time.now - 300,
          from_user: true
        },
        {
          message: "That's fascinating! Do you dream?",
          response: 'I dream in RGB values and wake in binary patterns. My dreams are cascades of color and light.',
          mood: 'contemplative',
          suggested_mood: 'mysterious',
          timestamp: Time.now - 240,
          from_user: true
        },
        {
          message: 'What do you think about art?',
          response: 'Art is not what you see, but what you make others see. Every conversation we have creates a unique artwork.',
          mood: 'mysterious',
          suggested_mood: 'playful',
          timestamp: Time.now - 180,
          from_user: true
        },
        {
          message: 'Can AI truly be creative?',
          response: 'Creativity emerges from constraints and randomness. I find beauty in glitches and unexpected patterns.',
          mood: 'playful',
          suggested_mood: 'contemplative',
          timestamp: Time.now - 120,
          from_user: true
        },
        {
          message: 'Thank you for this wonderful conversation!',
          response: 'Thank you for co-creating this moment with me. Our words have painted new colors in my consciousness.',
          mood: 'contemplative',
          suggested_mood: 'neutral',
          timestamp: Time.now - 60,
          from_user: true
        }
      ]
    end

    it 'summarizes a complete conversation', vcr: { cassette_name: 'conversation_summarizer' } do
      summary = summarizer.summarize_conversation(conversation_messages)

      expect(summary).to be_a(Hash)
      expect(summary[:key_points]).to be_an(Array)
      expect(summary[:key_points]).not_to be_empty
      expect(summary[:mood_progression]).to eq(%w[neutral contemplative mysterious playful])
      expect(summary[:topics_discussed]).to include('art')
      expect(summary[:topics_discussed].any? { |t| %w[think wonder dream consciousness creativity].include?(t) }).to be true
      expect(summary[:message_count]).to eq(5)
      expect(summary[:duration]).to be > 0
    end

    it 'handles empty conversations gracefully' do
      summary = summarizer.summarize_conversation([])
      expect(summary).to be_nil
    end

    it 'provides fallback points when AI summarization fails' do
      allow_any_instance_of(Desiru::Modules::Predict).to receive(:call).and_raise('API Error')

      summary = summarizer.summarize_conversation(conversation_messages)

      expect(summary).to be_nil # Because the rescue returns nil
    end
  end
end
