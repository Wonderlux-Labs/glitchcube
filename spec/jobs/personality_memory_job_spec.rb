# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/jobs/personality_memory_job'

RSpec.describe Jobs::PersonalityMemoryJob do
  let(:job) { described_class.new }

  describe '#perform' do
    context 'with insufficient messages' do
      it 'exits early when too few messages' do
        allow(Message).to receive_message_chain(:joins, :where, :where, :order).and_return([])

        # Allow the first info log, then expect the "not enough" message
        allow(job.logger).to receive(:info).with('🧠 Extracting personality memories from recent conversations...')
        expect(job.logger).to receive(:info).with(/Not enough messages/)
        expect(job).not_to receive(:extract_personality_memories)

        job.perform
      end
    end

    context 'with sufficient messages' do
      let(:messages) do
        [
          double(content: 'Someone tried to steal me!', role: 'user', created_at: 5.minutes.ago, conversation_id: 1),
          double(content: "That's wild! I'm an art piece!", role: 'assistant', created_at: 4.minutes.ago, conversation_id: 1),
          double(content: 'Yeah at the Man yesterday', role: 'user', created_at: 3.minutes.ago, conversation_id: 1)
        ]
      end

      before do
        allow(Message).to receive_message_chain(:joins, :where, :where, :order).and_return(messages)
        allow(messages).to receive_messages(count: 3, group_by: { 1 => messages })
      end

      it 'extracts memories from conversations' do
        # Use VCR to record/replay both HA and LLM calls
        # Allow any external calls within this cassette
        VCR.use_cassette('jobs/personality_memory_extraction',
                        match_requests_on: [:method, :uri], # Don't match on body for LLM calls
                        record: ENV['VCR_RECORD'] == 'true' ? :new_episodes : :none,
                        allow_playback_repeats: true) do
          allow(Memory).to receive(:where).and_return(double(exists?: false))
          expect(Memory).to receive(:create!).at_least(:once)

          job.perform
        end
      end

      it 'handles extraction failures gracefully' do
        allow(Services::LLMService).to receive(:complete).and_raise(StandardError.new('API Error'))

        expect(job.logger).to receive(:error).with(/Failed to extract memories/)
        expect { job.perform }.not_to raise_error
      end
    end
  end

  describe 'private methods' do
    describe '#fetch_location_data' do
      context 'with Home Assistant available' do
        it 'fetches location and coordinates' do
          # Use VCR to record/replay Home Assistant call
          VCR.use_cassette('jobs/fetch_location_data',
                          record: ENV['VCR_RECORD'] == 'true' ? :new_episodes : :none) do
            result = job.send(:fetch_location_data)
            
            # Assertions based on what HA returns (will vary based on cassette)
            expect(result).to have_key(:display)
            expect(result).to have_key(:coordinates)
            expect(result[:display]).to be_a(String)
          end
        end
      end

      context 'without Home Assistant' do
        it 'returns default location' do
          allow(GlitchCube.config.home_assistant).to receive(:url).and_return(nil)

          result = job.send(:fetch_location_data)
          expect(result[:display]).to eq('Somewhere in the dust')
          expect(result[:coordinates]).to be_nil
        end
      end
    end

    describe '#parse_event_time' do
      it 'parses common time patterns' do
        expect(job.send(:parse_event_time, 'in 30 minutes')).to be_within(1.minute).of(30.minutes.from_now)
        expect(job.send(:parse_event_time, 'in 2 hours')).to be_within(1.minute).of(2.hours.from_now)
        expect(job.send(:parse_event_time, 'tonight')).to be_within(1.hour).of(Time.now.end_of_day.change(hour: 21))
        expect(job.send(:parse_event_time, 'tomorrow')).to be_within(1.hour).of(Time.now.tomorrow.change(hour: 20))
      end

      it 'handles nil and blank strings' do
        expect(job.send(:parse_event_time, nil)).to be_nil
        expect(job.send(:parse_event_time, '')).to be_nil
      end
    end

    describe '#store_memories' do
      it 'avoids storing duplicate memories' do
        memory_data = {
          content: 'Test memory',
          data: { emotional_intensity: 0.5 }
        }

        # Simulate existing similar memory
        allow(Memory).to receive(:where).and_return(double(exists?: true))
        expect(Memory).not_to receive(:create!)

        job.send(:store_memories, [memory_data])
      end

      it 'stores unique memories' do
        memory_data = {
          content: 'Unique memory',
          data: { emotional_intensity: 0.7 }
        }

        allow(Memory).to receive(:where).and_return(double(exists?: false))
        expect(Memory).to receive(:create!).with(memory_data)

        job.send(:store_memories, [memory_data])
      end
    end
  end
end
