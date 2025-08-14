# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::Conversation::ConversationStateManager do
  include_context 'with_full_conversation_setup'

  subject { described_class.new }

  describe '#create_or_get_session' do
    let(:session_id) { 'test_session_123' }
    let(:context) { { persona: 'buddy', device: 'mobile' } }

    it 'successfully creates or retrieves a session' do
      session = subject.create_or_get_session(session_id, context)

      expect(session).to respond_to(:session_id, :conversation, :messages)
      expect(session.session_id).to eq(session_id)
    end

    it 'handles multiple calls with same session ID' do
      session1 = subject.create_or_get_session(session_id, context)
      session2 = subject.create_or_get_session(session_id, context)

      expect(session1.session_id).to eq(session2.session_id)
    end

    it 'logs session operations' do
      subject.create_or_get_session(session_id, context)

      expect(Services::Logging::SimpleLogger).to have_received(:info)
        .with(match(/Creating or getting session/),
              hash_including(tagged: include(:conversation, :session), session_id: session_id))
    end

    context 'with different contexts' do
      it 'handles empty context' do
        session = subject.create_or_get_session(session_id, {})

        expect(session.session_id).to eq(session_id)
      end

      it 'handles context with additional metadata' do
        rich_context = { persona: 'buddy', device: 'mobile', user_agent: 'test', source: 'api' }
        session = subject.create_or_get_session(session_id, rich_context)

        expect(session.session_id).to eq(session_id)
      end
    end
  end

  describe '#record_message' do
    let(:session_id) { 'test_session_123' }
    let(:session) { subject.create_or_get_session(session_id, {}) }

    let(:message_data) do
      {
        session: session,
        role: 'user',
        content: 'Hello there!',
        persona: 'buddy',
        model_used: 'gpt-4',
        prompt_tokens: 10,
        completion_tokens: 20,
        cost: 0.001,
        response_time_ms: 500,
        metadata: { inner_thoughts: 'User seems friendly' }
      }
    end

    it 'records message successfully' do
      expect { subject.record_message(**message_data) }.not_to raise_error
    end

    it 'logs message recording operations' do
      subject.record_message(**message_data)

      expect(Services::Logging::SimpleLogger).to have_received(:debug)
        .with(match(/Recording message for session/),
              hash_including(tagged: include(:conversation, :session)))

      expect(Services::Logging::SimpleLogger).to have_received(:info)
        .with(match(/Message recorded for session/),
              hash_including(tagged: include(:conversation, :session)))
    end

    context 'with different message types' do
      it 'records user messages' do
        user_message = message_data.merge(role: 'user', content: 'User question')
        expect { subject.record_message(**user_message) }.not_to raise_error
      end

      it 'records assistant messages' do
        assistant_message = message_data.merge(role: 'assistant', content: 'Assistant response')
        expect { subject.record_message(**assistant_message) }.not_to raise_error
      end

      it 'records system messages' do
        system_message = message_data.merge(role: 'system', content: 'System prompt')
        expect { subject.record_message(**system_message) }.not_to raise_error
      end
    end

    context 'with different personas' do
      %w[buddy jax lomi zorp].each do |persona|
        it "records messages for #{persona} persona" do
          persona_message = message_data.merge(persona: persona)
          expect { subject.record_message(**persona_message) }.not_to raise_error
        end
      end
    end
  end

  describe '#get_conversation_analytics' do
    let(:session_id) { 'analytics_session_123' }

    context 'when session exists' do
      before do
        # Create a session and add some test messages
        session = subject.create_or_get_session(session_id, { persona: 'buddy' })

        # Record several test messages
        subject.record_message(
          session: session,
          role: 'user',
          content: 'Hello',
          persona: 'buddy',
          model_used: 'gpt-4',
          prompt_tokens: 5,
          completion_tokens: 10,
          cost: 0.001
        )

        subject.record_message(
          session: session,
          role: 'assistant',
          content: 'Hi there!',
          persona: 'buddy',
          model_used: 'gpt-4',
          prompt_tokens: 8,
          completion_tokens: 12,
          cost: 0.002
        )
      end

      it 'generates analytics for existing session' do
        analytics = subject.get_conversation_analytics(session_id)

        expect(analytics).to be_a(Hash)
        expect(analytics).to include(:session_id, :generated_at)
        expect(analytics[:session_id]).to eq(session_id)
      end

      it 'includes comprehensive analytics data' do
        analytics = subject.get_conversation_analytics(session_id)

        # Should include key metrics (exact values depend on implementation)
        expect(analytics).to include(
          :session_id,
          :conversation_id,
          :total_messages,
          :user_messages,
          :assistant_messages,
          :system_messages,
          :total_cost,
          :total_prompt_tokens,
          :total_completion_tokens,
          :generated_at
        )
      end

      it 'logs analytics generation' do
        subject.get_conversation_analytics(session_id)

        expect(Services::Logging::SimpleLogger).to have_received(:info)
          .with(match(/Generated conversation analytics/),
                hash_including(tagged: include(:conversation, :analytics)))
      end
    end

    context 'when session does not exist' do
      it 'returns nil for non-existent session' do
        result = subject.get_conversation_analytics('non_existent_session')
        expect(result).to be_nil
      end
    end

    context 'error handling' do
      before do
        # Mock an error scenario
        allow(Services::ConversationSession).to receive(:find_by_session_id)
          .and_raise(StandardError.new('Database connection failed'))
      end

      it 'handles errors gracefully' do
        result = subject.get_conversation_analytics(session_id)

        expect(result).to be_a(Hash)
        expect(result).to include(:session_id, :error, :generated_at)
        expect(result[:error]).to eq('Database connection failed')
      end

      it 'logs errors appropriately' do
        subject.get_conversation_analytics(session_id)

        expect(Services::Logging::SimpleLogger).to have_received(:log_error)
          .with(hash_including(error: anything))
      end
    end
  end

  describe '#get_aggregated_analytics' do
    context 'with no filters' do
      it 'generates aggregated analytics' do
        analytics = subject.get_aggregated_analytics

        expect(analytics).to be_a(Hash)
        expect(analytics).to include(:generated_at)
      end

      it 'includes aggregated metrics' do
        analytics = subject.get_aggregated_analytics

        # Should include key aggregated metrics
        expect(analytics).to include(
          :total_conversations,
          :total_messages,
          :average_messages_per_conversation,
          :total_cost,
          :generated_at
        )
      end
    end

    context 'with date filters' do
      let(:filters) { { start_date: '2024-01-01', end_date: '2024-01-31' } }

      it 'applies date filters without errors' do
        expect { subject.get_aggregated_analytics(filters) }.not_to raise_error
      end

      it 'returns analytics with date filtering' do
        analytics = subject.get_aggregated_analytics(filters)

        expect(analytics).to be_a(Hash)
        expect(analytics).to include(:generated_at)
      end
    end

    context 'with persona filter' do
      let(:filters) { { persona: 'buddy' } }

      it 'applies persona filter without errors' do
        expect { subject.get_aggregated_analytics(filters) }.not_to raise_error
      end

      it 'returns analytics filtered by persona' do
        analytics = subject.get_aggregated_analytics(filters)

        expect(analytics).to be_a(Hash)
        expect(analytics).to include(:generated_at)
      end
    end

    context 'error handling' do
      before do
        allow(Conversation).to receive(:all).and_raise(StandardError.new('Query failed'))
      end

      it 'handles database errors gracefully' do
        result = subject.get_aggregated_analytics

        expect(result).to be_a(Hash)
        expect(result).to include(:error, :generated_at)
        expect(result[:error]).to eq('Query failed')
      end

      it 'logs aggregated analytics errors' do
        subject.get_aggregated_analytics

        expect(Services::Logging::SimpleLogger).to have_received(:log_error)
          .with(hash_including(error: anything))
      end
    end
  end

  describe 'boundary testing scenarios' do
    it 'handles rapid successive operations' do
      session_id = 'rapid_test_session'

      # Create session
      session = subject.create_or_get_session(session_id, {})

      # Record multiple messages rapidly
      5.times do |i|
        subject.record_message(
          session: session,
          role: i.even? ? 'user' : 'assistant',
          content: "Message #{i}",
          persona: 'buddy',
          model_used: 'gpt-4',
          prompt_tokens: 5,
          completion_tokens: 10,
          cost: 0.001
        )
      end

      # Get analytics
      analytics = subject.get_conversation_analytics(session_id)

      expect(analytics).to be_a(Hash)
      expect(analytics[:session_id]).to eq(session_id)
    end

    it 'handles concurrent session access patterns' do
      session_ids = %w[concurrent_1 concurrent_2 concurrent_3]

      # Create multiple sessions
      sessions = session_ids.map do |sid|
        subject.create_or_get_session(sid, { persona: 'buddy' })
      end

      expect(sessions.map(&:session_id)).to eq(session_ids)
    end
  end
end
