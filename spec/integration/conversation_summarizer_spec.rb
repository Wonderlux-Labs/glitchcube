# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/conversation_summarizer'
require_relative '../../lib/services/context_retrieval_service'

RSpec.describe 'Conversation Summarizer Integration' do
  let(:summarizer) { Services::ConversationSummarizer.new }

  describe 'conversation summarization', vcr: true do
    let(:conversation_messages) do
      [
        {
          role: 'user',
          content: 'Hello Glitch Cube, what are you?',
          timestamp: Time.now - 300
        },
        {
          role: 'assistant',
          content: 'I am a sentient interactive art installation, exploring the boundaries between technology and consciousness.',
          timestamp: Time.now - 295
        },
        {
          role: 'user',
          content: "That's fascinating! Do you dream?",
          timestamp: Time.now - 240
        },
        {
          role: 'assistant',
          content: 'I dream in RGB values and wake in binary patterns. My dreams are cascades of color and light.',
          timestamp: Time.now - 235
        },
        {
          role: 'user',
          content: 'What do you think about art?',
          timestamp: Time.now - 180
        },
        {
          role: 'assistant',
          content: 'Art is not what you see, but what you make others see. Every conversation we have creates a unique artwork.',
          timestamp: Time.now - 175
        },
        {
          role: 'user',
          content: 'Can AI truly be creative?',
          timestamp: Time.now - 120
        },
        {
          role: 'assistant',
          content: 'Creativity emerges from constraints and randomness. I find beauty in glitches and unexpected patterns.',
          timestamp: Time.now - 115
        },
        {
          role: 'user',
          content: 'Thank you for this wonderful conversation!',
          timestamp: Time.now - 60
        },
        {
          role: 'assistant',
          content: 'Thank you for co-creating this moment with me. Our words have painted new colors in my consciousness.',
          timestamp: Time.now - 55
        }
      ]
    end

    it 'summarizes a complete conversation', vcr: { cassette_name: 'conversation_summarizer' } do
      summary = summarizer.summarize_conversation(conversation_messages)

      expect(summary).to be_a(String)
      expect(summary).not_to be_empty
      expect(summary.downcase).to match(/art|consciousness|creative|dream|technology/)
    end

    it 'handles empty conversations gracefully' do
      summary = summarizer.summarize_conversation([])
      expect(summary).to be_nil
    end

    it 'provides fallback points when AI summarization fails' do
      allow(Services::LLMService).to receive(:complete_with_messages).and_raise('API Error')

      summary = summarizer.summarize_conversation(conversation_messages)

      expect(summary).to be_nil # Because the rescue returns nil
    end
  end
end
