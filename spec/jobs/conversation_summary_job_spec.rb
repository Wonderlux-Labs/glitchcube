# frozen_string_literal: true

require 'spec_helper'
require 'sidekiq/testing'
require_relative '../../lib/jobs/conversation_summary_job'
require_relative '../../lib/jobs/memory_consolidation_job'

RSpec.describe Jobs::ConversationSummaryJob do
  before do
    Sidekiq::Testing.fake!
  end

  after do
    Sidekiq::Worker.clear_all
  end

  let(:conversation_messages) do
    [
      {
        'message' => 'What is consciousness?',
        'response' => 'Consciousness is the experience of being aware.',
        'mood' => 'contemplative',
        'timestamp' => Time.now.iso8601
      },
      {
        'message' => 'Do you think about art?',
        'response' => 'Art is my primary mode of expression and understanding.',
        'mood' => 'contemplative',
        'timestamp' => Time.now.iso8601
      }
    ]
  end

  describe '#perform' do
    it 'enqueues the job' do
      expect do
        described_class.perform_async('session-123', conversation_messages)
      end.to change(described_class.jobs, :size).by(1)
    end

    it 'includes correct arguments' do
      described_class.perform_async('session-123', conversation_messages, { 'location' => 'gallery' })

      job = described_class.jobs.last
      expect(job['args']).to eq(['session-123', conversation_messages, { 'location' => 'gallery' }])
    end

    context 'when executing' do
      it 'triggers memory consolidation for significant conversations' do
        allow_any_instance_of(Services::ConversationSummarizer).to receive(:summarize_conversation).and_return({
                                                                                                                 'message_count' => 6,
                                                                                                                 'topics_discussed' => %w[consciousness art],
                                                                                                                 'duration' => 400,
                                                                                                                 'key_points' => ['Deep discussion about digital consciousness']
                                                                                                               })

        expect(Jobs::MemoryConsolidationJob).to receive(:perform_async)

        job = described_class.new
        job.perform('session-123', conversation_messages)
      end

      it 'does not trigger memory consolidation for brief conversations' do
        allow_any_instance_of(Services::ConversationSummarizer).to receive(:summarize_conversation).and_return({
                                                                                                                 'message_count' => 2,
                                                                                                                 'topics_discussed' => ['weather'],
                                                                                                                 'duration' => 60,
                                                                                                                 'key_points' => ['Brief chat about the weather']
                                                                                                               })

        expect(Jobs::MemoryConsolidationJob).not_to receive(:perform_async)

        job = described_class.new
        job.perform('session-123', conversation_messages)
      end
    end
  end
end
