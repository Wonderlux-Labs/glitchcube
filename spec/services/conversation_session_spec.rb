# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/conversation_session'

RSpec.describe Services::ConversationSession do
  let(:session_id) { 'test-session-123' }
  let(:redis) { instance_double(Redis) }

  before do
    # Reset class instance variable to prevent leaking between tests
    described_class.instance_variable_set(:@redis, nil)

    allow(GlitchCube.config).to receive(:redis_connection).and_return(redis)
    allow(redis).to receive(:ping).and_return('PONG')
  end

  after do
    # Clean up class instance variable
    described_class.instance_variable_set(:@redis, nil)
  end

  describe '.find_or_create' do
    context 'when session exists' do
      let(:existing_data) do
        {
          session_id: session_id,
          metadata: { source: 'api', started_at: Time.current.iso8601 },
          messages: [{ role: 'user', content: 'Hello' }]
        }.to_json
      end

      before do
        allow(redis).to receive(:exists?).with("conversation:#{session_id}").and_return(true)
        allow(redis).to receive(:get).with("conversation:#{session_id}").and_return(existing_data)
        allow(redis).to receive(:expire)
      end

      it 'loads existing session' do
        session = described_class.find_or_create(session_id: session_id)

        expect(session.session_id).to eq(session_id)
        expect(session.metadata[:source]).to eq('api')
      end

      it 'refreshes TTL on load' do
        expect(redis).to receive(:expire).with("conversation:#{session_id}", 3600)

        described_class.find_or_create(session_id: session_id)
      end
    end

    context 'when session does not exist' do
      before do
        allow(redis).to receive(:exists?).with(anything).and_return(false)
        allow(redis).to receive(:setex)
      end

      it 'creates new session with generated ID' do
        session = described_class.find_or_create

        expect(session.session_id).to be_a(String)
        expect(session.session_id.length).to eq(36) # UUID length
      end

      it 'creates new session with provided context' do
        context = { source: 'webhook', persona: 'playful' }
        session = described_class.find_or_create(context: context)

        expect(session.metadata[:source]).to eq('webhook')
        expect(session.metadata[:last_persona]).to eq('playful')
      end

      it 'saves new session to Redis' do
        expect(redis).to receive(:setex).with(
          /conversation:/,
          3600,
          a_string_including('"source":"api"')
        )

        described_class.find_or_create(session_id: session_id)
      end
    end
  end

  describe '.find' do
    context 'when session exists' do
      let(:existing_data) do
        {
          session_id: session_id,
          metadata: { source: 'api' },
          messages: []
        }.to_json
      end

      before do
        allow(redis).to receive(:exists?).with("conversation:#{session_id}").and_return(true)
        allow(redis).to receive(:get).with("conversation:#{session_id}").and_return(existing_data)
        allow(redis).to receive(:expire)
      end

      it 'returns the session' do
        session = described_class.find(session_id)

        expect(session).to be_a(described_class)
        expect(session.session_id).to eq(session_id)
      end
    end

    context 'when session does not exist' do
      before do
        allow(redis).to receive(:exists?).with("conversation:#{session_id}").and_return(false)
      end

      it 'returns nil' do
        session = described_class.find(session_id)

        expect(session).to be_nil
      end
    end
  end

  describe '#add_message' do
    let(:session) { described_class.new(session_id) }

    before do
      allow(redis).to receive(:setex)
      session.initialize_session
    end

    context 'adding user message' do
      it 'increments interaction count' do
        expect do
          session.add_message(role: 'user', content: 'Hello')
        end.to change { session.metadata[:interaction_count] }.from(0).to(1)
      end

      it 'updates last activity' do
        session.add_message(role: 'user', content: 'Hello')

        expect(session.metadata[:last_activity]).to be_a(String)
      end
    end

    context 'adding assistant message' do
      it 'updates cost and tokens' do
        session.add_message(
          role: 'assistant',
          content: 'Hello there!',
          cost: 0.001,
          prompt_tokens: 10,
          completion_tokens: 5
        )

        expect(session.metadata[:total_cost]).to eq(0.001)
        expect(session.metadata[:total_tokens]).to eq(15)
      end

      it 'updates persona' do
        session.add_message(
          role: 'assistant',
          content: 'Response',
          persona: 'playful'
        )

        expect(session.metadata[:last_persona]).to eq('playful')
      end
    end

    it 'saves to Redis after adding' do
      expect(redis).to receive(:setex).with(
        "conversation:#{session_id}",
        3600,
        a_string_including('"Hello"')
      )

      session.add_message(role: 'user', content: 'Hello')
    end
  end

  describe '#messages_for_llm' do
    let(:session) { described_class.new(session_id) }

    before do
      allow(redis).to receive(:setex)
      session.initialize_session

      session.add_message(role: 'user', content: 'Hello', extra: 'data')
      session.add_message(role: 'assistant', content: 'Hi there!')
    end

    it 'returns messages formatted for LLM' do
      messages = session.messages_for_llm

      expect(messages).to eq([
                               { role: 'user', content: 'Hello' },
                               { role: 'assistant', content: 'Hi there!' }
                             ])
    end

    it 'respects message limit' do
      10.times { |i| session.add_message(role: 'user', content: "Message #{i}") }

      messages = session.messages_for_llm(limit: 3)

      expect(messages.size).to eq(3)
      expect(messages.last[:content]).to eq('Message 9')
    end
  end

  describe '#end_conversation' do
    let(:session) { described_class.new(session_id) }

    before do
      allow(redis).to receive(:setex)
      session.initialize_session
    end

    it 'sets ended_at timestamp' do
      session.end_conversation

      expect(session.metadata[:ended_at]).to be_a(String)
    end

    it 'sets end reason if provided' do
      session.end_conversation(reason: 'user_goodbye')

      expect(session.metadata[:end_reason]).to eq('user_goodbye')
    end

    it 'saves to Redis' do
      expect(redis).to receive(:setex)

      session.end_conversation
    end
  end

  describe '#summary' do
    let(:session) { described_class.new(session_id) }

    before do
      allow(redis).to receive(:setex)
      session.initialize_session
      session.add_message(role: 'user', content: 'Hello')
      session.add_message(role: 'assistant', content: 'Hi!', cost: 0.001, prompt_tokens: 5, completion_tokens: 3)
    end

    it 'returns session summary' do
      summary = session.summary

      expect(summary[:session_id]).to eq(session_id)
      expect(summary[:message_count]).to eq(2)
      expect(summary[:total_cost]).to eq(0.001)
      expect(summary[:total_tokens]).to eq(8)
      expect(summary[:interaction_count]).to eq(1)
    end
  end

  describe 'Redis unavailable handling' do
    before do
      allow(redis).to receive(:ping).and_raise(Redis::CannotConnectError)
    end

    it 'returns false for exists? when Redis unavailable' do
      session = described_class.new(session_id)

      expect(session.exists?).to be false
    end

    it 'returns false for save when Redis unavailable' do
      session = described_class.new(session_id)
      session.initialize_session

      expect(session.save).to be false
    end

    it 'creates session even when Redis unavailable' do
      session = described_class.find_or_create(session_id: session_id)

      expect(session).to be_a(described_class)
      expect(session.session_id).to eq(session_id)
    end
  end

  describe '.cleanup_expired' do
    before do
      allow(redis).to receive(:keys).with('conversation:*').and_return([
                                                                         'conversation:session1',
                                                                         'conversation:session2'
                                                                       ])
    end

    it 'sets TTL for sessions without expiry' do
      allow(redis).to receive(:ttl).and_return(-1) # No TTL
      expect(redis).to receive(:expire).twice

      described_class.cleanup_expired
    end

    it 'counts expired sessions' do
      allow(redis).to receive(:ttl).and_return(-2) # Expired

      count = described_class.cleanup_expired

      expect(count).to eq(2)
    end
  end
end
