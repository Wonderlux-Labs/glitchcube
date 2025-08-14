# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Jobs::PersonalSummarizerJob do
  let(:job) { described_class.new }

  describe '#perform' do
    context 'when a summary was generated recently' do
      before do
        Summary.create!(
          summary_type: 'personal',
          period: 'hourly',
          content: 'Recent summary',
          created_at: 30.minutes.ago
        )
      end

      it 'does not create a new summary' do
        expect { job.perform }.not_to change(Summary, :count)
      end
    end

    context 'when no recent summary exists' do
      context 'with no recent messages' do
        it 'does not create a summary' do
          expect { job.perform }.not_to change(Summary, :count)
        end
      end

      context 'with recent messages' do
        let!(:conversation) { Conversation.create!(session_id: 'test-123', persona: 'buddy') }
        let!(:message1) do
          Message.create!(
            conversation: conversation,
            role: 'assistant',
            content: 'Battery at 30%, getting tired of these questions',
            created_at: 30.minutes.ago
          )
        end
        let!(:message2) do
          Message.create!(
            conversation: conversation,
            role: 'assistant',
            content: 'Need to find those flux capacitors soon',
            created_at: 15.minutes.ago
          )
        end

        before do
          response = double('LLMResponse', content: 'Battery running low at 30%, feeling frustrated with repetitive questions. The search for flux capacitors continues.')
          allow(Services::Llm::LLMService).to receive(:complete).and_return(response)
        end

        it 'creates a personal summary' do
          expect { job.perform }.to change(Summary, :count).by(1)
        end

        it 'creates summary with correct attributes' do
          job.perform
          summary = Summary.last

          expect(summary.summary_type).to eq('personal')
          expect(summary.period).to eq('hourly')
          expect(summary.content).to include('Battery running low')
          expect(summary.metadata['message_count']).to eq(2)
        end

        it 'includes message content in LLM prompt' do
          expect(Services::Llm::LLMService).to receive(:complete) do |args|
            expect(args[:user_message]).to include('Battery at 30%')
            expect(args[:user_message]).to include('flux capacitors')
            double('LLMResponse', content: 'Test summary')
          end

          job.perform
        end
      end
    end

    context 'when an error occurs' do
      before do
        allow(Services::Llm::LLMService).to receive(:complete).and_raise(StandardError, 'LLM error')
      end

      let!(:conversation) { Conversation.create!(session_id: 'error-test') }
      let!(:message) do
        Message.create!(
          conversation: conversation,
          role: 'assistant',
          content: 'Test message',
          created_at: 5.minutes.ago
        )
      end

      it 'logs the error and re-raises' do
        expect(Services::Logging::SimpleLogger).to receive(:error).with(/PersonalSummarizerJob failed/)
        expect { job.perform }.to raise_error(StandardError, 'LLM error')
      end
    end
  end
end
