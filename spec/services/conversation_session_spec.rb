# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/conversation_session'

RSpec.describe Services::ConversationSession do
  let(:session_id) { 'test-session-123' }
  let(:conversation) do
    double(
      'Conversation',
      session_id: session_id,
      source: 'api',
      persona: 'neutral',
      started_at: Time.current,
      ended_at: nil,
      end_reason: nil,
      total_cost: 0.0,
      total_tokens: 0,
      message_count: 0,
      metadata: {}
    )
  end

  describe '.find_or_create' do
    context 'when session exists' do
      before do
        allow(Conversation).to receive(:find_or_create_by).with(session_id: session_id).and_return(conversation)
      end

      it 'loads existing session' do
        session = described_class.find_or_create(session_id: session_id)

        expect(session.session_id).to eq(session_id)
        expect(session.metadata[:source]).to eq('api')
      end

      it 'does not create duplicate session' do
        expect(Conversation).to receive(:find_or_create_by).once

        described_class.find_or_create(session_id: session_id)
      end
    end

    context 'when session does not exist' do
      let(:new_conversation) { double('Conversation', session_id: session_id, source: 'api', persona: 'neutral') }

      before do
        allow(Conversation).to receive(:find_or_create_by).and_yield(new_conversation).and_return(new_conversation)
        allow(new_conversation).to receive_messages(
          'source=': nil,
          'persona=': nil,
          'started_at=': nil,
          'metadata=': nil
        )
      end

      it 'creates new session with generated ID' do
        allow(SecureRandom).to receive(:uuid).and_return('generated-uuid-123')
        allow(new_conversation).to receive(:session_id).and_return('generated-uuid-123')

        session = described_class.find_or_create

        expect(session.session_id).to eq('generated-uuid-123')
      end

      it 'creates new session with provided context' do
        context = { source: 'webhook', persona: 'playful' }
        expect(new_conversation).to receive('source=').with('webhook')
        expect(new_conversation).to receive('persona=').with('playful')

        described_class.find_or_create(context: context)
      end

      it 'saves new session to database' do
        expect(Conversation).to receive(:find_or_create_by).with(session_id: session_id)

        described_class.find_or_create(session_id: session_id)
      end
    end
  end

  describe '.find' do
    context 'when session exists' do
      before do
        allow(Conversation).to receive(:find_by).with(session_id: session_id).and_return(conversation)
      end

      it 'returns the session' do
        session = described_class.find(session_id)

        expect(session).to be_a(described_class)
        expect(session.session_id).to eq(session_id)
      end
    end

    context 'when session does not exist' do
      before do
        allow(Conversation).to receive(:find_by).with(session_id: session_id).and_return(nil)
      end

      it 'returns nil' do
        session = described_class.find(session_id)

        expect(session).to be_nil
      end
    end
  end

  describe '#add_message' do
    let(:session) { described_class.new(conversation) }
    let(:message) { double('Message', role: 'user', content: 'Hello') }

    before do
      allow(conversation).to receive(:add_message).and_return(message)
      allow(conversation).to receive(:update!)
    end

    context 'adding user message' do
      it 'delegates to conversation model' do
        expect(conversation).to receive(:add_message).with(
          role: 'user',
          content: 'Hello'
        )

        session.add_message(role: 'user', content: 'Hello')
      end

      it 'returns the created message' do
        result = session.add_message(role: 'user', content: 'Hello')

        expect(result).to eq(message)
      end
    end

    context 'adding assistant message' do
      let(:assistant_message) { double('Message', role: 'assistant', content: 'Hello there!') }

      before do
        allow(conversation).to receive(:add_message).and_return(assistant_message)
        allow(conversation).to receive_messages(
          total_cost: 0.0,
          total_tokens: 0
        )
      end

      it 'updates conversation totals' do
        expect(conversation).to receive(:update!).with(
          hash_including(
            total_cost: 0.001,
            total_tokens: 15
          )
        )

        session.add_message(
          role: 'assistant',
          content: 'Hello there!',
          cost: 0.001,
          prompt_tokens: 10,
          completion_tokens: 5
        )
      end

      it 'updates persona if provided' do
        expect(conversation).to receive(:update!).with(
          hash_including(persona: 'playful')
        )

        session.add_message(
          role: 'assistant',
          content: 'Response',
          persona: 'playful'
        )
      end
    end
  end

  describe '#messages_for_llm' do
    let(:session) { described_class.new(conversation) }
    let(:messages_relation) { double('Messages') }
    let(:message1) { double('Message', role: 'user', content: 'Hello') }
    let(:message2) { double('Message', role: 'assistant', content: 'Hi there!') }

    before do
      allow(conversation).to receive(:messages).and_return(messages_relation)
      allow(messages_relation).to receive(:order).with(created_at: :desc).and_return(messages_relation)
      allow(messages_relation).to receive_messages(limit: messages_relation, reverse: [message1, message2])
    end

    it 'returns messages formatted for LLM' do
      allow(messages_relation).to receive(:limit).with(20).and_return(messages_relation)

      messages = session.messages_for_llm

      expect(messages).to eq([
                               { role: 'user', content: 'Hello' },
                               { role: 'assistant', content: 'Hi there!' }
                             ])
    end

    it 'respects message limit' do
      expect(messages_relation).to receive(:limit).with(3).and_return(messages_relation)
      allow(messages_relation).to receive(:reverse).and_return([message1, message2])

      messages = session.messages_for_llm(limit: 3)

      expect(messages.size).to eq(2) # Only 2 messages returned by mock
    end
  end

  describe '#end_conversation' do
    let(:session) { described_class.new(conversation) }

    before do
      allow(conversation).to receive(:end!)
      allow(conversation).to receive(:update!)
      # Mock ConversationSummaryJob if it exists
      allow(ConversationSummaryJob).to receive(:perform_async) if defined?(ConversationSummaryJob)
    end

    it 'marks conversation as ended' do
      expect(conversation).to receive(:end!)

      session.end_conversation
    end

    it 'sets end reason if provided' do
      expect(conversation).to receive(:update!).with(end_reason: 'user_goodbye')

      session.end_conversation(reason: 'user_goodbye')
    end

    it 'returns true on success' do
      result = session.end_conversation

      expect(result).to be true
    end
  end

  describe '#summary' do
    let(:session) { described_class.new(conversation) }
    let(:summary_data) do
      {
        session_id: session_id,
        message_count: 2,
        total_cost: 0.001,
        total_tokens: 8
      }
    end

    before do
      allow(conversation).to receive(:summary).and_return(summary_data)
    end

    it 'returns session summary' do
      summary = session.summary

      expect(summary[:session_id]).to eq(session_id)
      expect(summary[:message_count]).to eq(2)
      expect(summary[:total_cost]).to eq(0.001)
      expect(summary[:total_tokens]).to eq(8)
    end
  end

  describe '#exists?' do
    context 'with valid conversation' do
      let(:session) { described_class.new(conversation) }

      it 'returns true when conversation exists' do
        expect(session.exists?).to be true
      end
    end

    context 'with nil conversation stored internally' do
      let(:session) { described_class.new(conversation) }

      before do
        # Simulate nil conversation by setting instance variable directly
        session.instance_variable_set(:@conversation, nil)
      end

      it 'returns false when conversation is nil' do
        expect(session.exists?).to be false
      end
    end
  end

  describe '#save' do
    let(:session) { described_class.new(conversation) }

    it 'delegates save to conversation model' do
      expect(conversation).to receive(:save).and_return(true)

      expect(session.save).to be true
    end

    it 'handles conversation model save failures' do
      expect(conversation).to receive(:save).and_return(false)

      expect(session.save).to be false
    end
  end

  describe '#metadata (compatibility)' do
    let(:session) { described_class.new(conversation) }
    let(:start_time) { Time.current }

    before do
      allow(conversation).to receive_messages(
        source: 'api',
        started_at: start_time,
        message_count: 3,
        total_cost: 0.05,
        total_tokens: 100,
        persona: 'playful',
        metadata: { custom: 'data' }
      )
    end

    it 'provides compatibility metadata format' do
      metadata = session.metadata

      expect(metadata).to include(
        source: 'api',
        interaction_count: 3,
        total_cost: 0.05,
        total_tokens: 100,
        last_persona: 'playful',
        context: { custom: 'data' }
      )
      expect(metadata[:started_at]).to eq(start_time)
    end
  end
end
