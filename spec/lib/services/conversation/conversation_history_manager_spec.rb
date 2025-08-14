# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::Conversation::HistoryManager do
  include_context 'with_full_conversation_setup'

  subject { described_class.new }

  let(:conversation_id) { 'conv_123' }
  let(:valid_message) do
    {
      role: 'user',
      content: 'Hello world',
      timestamp: Time.now.utc.iso8601,
      context: { device: 'mobile' }
    }
  end

  let(:assistant_message) do
    {
      role: 'assistant',
      content: 'Hello! How can I help you today?',
      timestamp: Time.now.utc.iso8601,
      context: { model: 'gpt-4' }
    }
  end

  describe '#save_message' do
    context 'with valid message' do
      it 'saves user messages successfully' do
        expect { subject.save_message(conversation_id, valid_message) }.not_to raise_error
      end

      it 'saves assistant messages successfully' do
        expect { subject.save_message(conversation_id, assistant_message) }.not_to raise_error
      end

      it 'handles different message roles' do
        system_message = valid_message.merge(role: 'system', content: 'System message')

        expect { subject.save_message(conversation_id, system_message) }.not_to raise_error
      end

      it 'logs successful saves' do
        subject.save_message(conversation_id, valid_message)

        expect(Services::Logging::SimpleLogger).to have_received(:info)
          .with(match(/Message saved/), hash_including(:conversation_id))
      end
    end

    context 'with invalid message structure' do
      let(:invalid_message) { { role: 'invalid_role', content: '' } }

      it 'handles invalid messages gracefully' do
        expect do
          subject.save_message(conversation_id, invalid_message)
        end.not_to raise_error
      end

      it 'logs validation errors appropriately' do
        allow(subject).to receive(:validate_message).and_raise(StandardError.new('Validation failed'))

        expect { subject.save_message(conversation_id, valid_message) }.not_to raise_error

        expect(Services::Logging::SimpleLogger).to have_received(:log_error)
          .with(hash_including(error: 'Validation failed'))
      end
    end

    context 'with different conversation IDs' do
      it 'handles multiple conversations' do
        conv_ids = %w[conv_1 conv_2 conv_3]

        conv_ids.each do |cid|
          expect { subject.save_message(cid, valid_message) }.not_to raise_error
        end
      end
    end
  end

  describe '#get_messages' do
    before do
      # Set up some test messages
      subject.save_message(conversation_id, valid_message)
      subject.save_message(conversation_id, assistant_message)
    end

    it 'retrieves messages for conversation' do
      messages = subject.get_messages(conversation_id)

      expect(messages).to be_an(Array)
    end

    it 'handles limit parameter' do
      messages = subject.get_messages(conversation_id, limit: 1)

      expect(messages).to be_an(Array)
    end

    it 'handles offset parameter' do
      messages = subject.get_messages(conversation_id, offset: 1)

      expect(messages).to be_an(Array)
    end

    it 'returns empty array for non-existent conversation' do
      messages = subject.get_messages('non_existent_conv')

      expect(messages).to eq([])
    end

    it 'logs message retrieval operations' do
      subject.get_messages(conversation_id)

      expect(Services::Logging::SimpleLogger).to have_received(:debug)
        .with(match(/Retrieving messages/), hash_including(:conversation_id))
    end
  end

  describe '#get_recent_messages' do
    before do
      # Add multiple messages with different timestamps
      3.times do |i|
        message = valid_message.merge(
          content: "Message #{i}",
          timestamp: (Time.now - i.minutes).utc.iso8601
        )
        subject.save_message(conversation_id, message)
      end
    end

    it 'retrieves recent messages' do
      messages = subject.get_recent_messages(conversation_id)

      expect(messages).to be_an(Array)
    end

    it 'respects count limits' do
      messages = subject.get_recent_messages(conversation_id, count: 2)

      expect(messages).to be_an(Array)
    end

    it 'handles time window filtering' do
      messages = subject.get_recent_messages(conversation_id, since: 1.hour.ago)

      expect(messages).to be_an(Array)
    end
  end

  describe '#clear_conversation' do
    before do
      subject.save_message(conversation_id, valid_message)
      subject.save_message(conversation_id, assistant_message)
    end

    it 'clears conversation messages' do
      expect { subject.clear_conversation(conversation_id) }.not_to raise_error
    end

    it 'logs conversation clearing' do
      subject.clear_conversation(conversation_id)

      expect(Services::Logging::SimpleLogger).to have_received(:info)
        .with(match(/Cleared conversation/), hash_including(:conversation_id))
    end

    it 'handles clearing non-existent conversations' do
      expect { subject.clear_conversation('non_existent') }.not_to raise_error
    end
  end

  describe '#get_conversation_summary' do
    before do
      subject.save_message(conversation_id, valid_message)
      subject.save_message(conversation_id, assistant_message)
    end

    it 'generates conversation summary' do
      summary = subject.get_conversation_summary(conversation_id)

      expect(summary).to be_a(Hash)
      expect(summary).to include(:conversation_id, :message_count, :created_at)
    end

    it 'includes metadata in summary' do
      summary = subject.get_conversation_summary(conversation_id)

      expect(summary[:conversation_id]).to eq(conversation_id)
      expect(summary[:message_count]).to be_a(Integer)
      expect(summary[:message_count]).to be >= 0
    end

    it 'handles summaries for empty conversations' do
      summary = subject.get_conversation_summary('empty_conv')

      expect(summary).to be_a(Hash)
      expect(summary[:message_count]).to eq(0)
    end
  end

  describe 'error handling and edge cases' do
    it 'handles storage adapter failures gracefully' do
      # Simulate storage failure
      allow_any_instance_of(subject.class).to receive(:save_message)
        .and_raise(StandardError.new('Storage unavailable'))

      expect { subject.save_message(conversation_id, valid_message) }.not_to raise_error
    end

    it 'handles malformed message data' do
      malformed_messages = [
        nil,
        {},
        { role: nil },
        { content: nil },
        { role: 'user' }, # missing content
        { content: 'test' } # missing role
      ]

      malformed_messages.each do |msg|
        expect { subject.save_message(conversation_id, msg) }.not_to raise_error
      end
    end

    it 'handles extremely long messages' do
      long_message = valid_message.merge(content: 'x' * 10_000)

      expect { subject.save_message(conversation_id, long_message) }.not_to raise_error
    end

    it 'handles special characters in content' do
      special_message = valid_message.merge(
        content: "Special chars: 🎭 emojis, <html>, {json: true}, 'quotes', \"double quotes\""
      )

      expect { subject.save_message(conversation_id, special_message) }.not_to raise_error
    end
  end

  describe 'performance and boundary testing' do
    it 'handles rapid message saving' do
      10.times do |i|
        message = valid_message.merge(content: "Rapid message #{i}")
        expect { subject.save_message(conversation_id, message) }.not_to raise_error
      end
    end

    it 'handles concurrent conversation operations' do
      conversations = %w[conv_a conv_b conv_c]

      conversations.each do |cid|
        expect { subject.save_message(cid, valid_message) }.not_to raise_error
        expect { subject.get_messages(cid) }.not_to raise_error
        expect { subject.get_conversation_summary(cid) }.not_to raise_error
      end
    end
  end
end
