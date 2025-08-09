# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/jobs/personality_memory_job'

RSpec.describe Jobs::PersonalityMemoryJob do
  let(:job) { described_class.new }

  describe '#perform' do
    context 'with insufficient messages' do
      it 'exits early when too few messages', :vcr do
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
        # Mock the config.ai object to include small_model
        ai_config = double('ai_config', 
          small_model: 'openai/gpt-4o-mini',
          default_model: 'google/gemini-2.5-flash',
          temperature: 0.8,
          max_tokens: 200,
          max_session_messages: 10
        )
        allow(GlitchCube.config).to receive(:ai).and_return(ai_config)
      end

      xit 'extracts memories from conversations', :vcr do
        # Use VCR to record/replay both HA and LLM calls
        # Allow any external calls within this cassette
        allow(Memory).to receive(:where).and_return(double(exists?: false))
        expect(Memory).to receive(:create!).at_least(:once)
        job.perform
      end

      it 'handles extraction failures gracefully', :vcr do
        allow(Services::LLMService).to receive(:complete).and_raise(StandardError.new('API Error'))
        # Allow any log_api_call from other services (like HomeAssistantClient)
        allow(Services::LoggerService).to receive(:log_api_call).and_call_original
        # The extract_personality_memories method catches the error and returns []
        # So it logs the error but doesn't re-raise it - the job continues
        expect(Services::LoggerService).to receive(:log_api_call).with(hash_including(
                                                                         service: 'application',
                                                                         status: 500,
                                                                         error: /StandardError: API Error/
                                                                       )).at_least(:once)
        # Allow the logger to log info messages
        allow(job.logger).to receive(:info).and_call_original
        # The job should complete without raising an error
        # (extract_personality_memories returns [] on failure, not re-raising)
        expect { job.perform }.not_to raise_error
      end
    end
  end

  describe 'private methods' do
    describe '#fetch_location_data' do
      context 'with Home Assistant available' do
        it 'fetches location and coordinates', :vcr do
          # Use VCR to record/replay Home Assistant call
          result = job.send(:fetch_location_data)

          # Assertions based on what HA returns (will vary based on cassette)
          expect(result).to have_key(:display)
          expect(result).to have_key(:coordinates)
          expect(result[:display]).to be_a(String)
        end
      end

      context 'without Home Assistant' do
        it 'returns default location', :vcr do
          allow(GlitchCube.config.home_assistant).to receive(:url).and_return(nil)

          result = job.send(:fetch_location_data)
          expect(result[:display]).to eq('Somewhere in the dust')
          expect(result[:coordinates]).to be_nil
        end
      end
    end

    describe '#parse_event_time' do
      it 'parses common time patterns', :vcr do
        expect(job.send(:parse_event_time, 'in 30 minutes')).to be_within(1.minute).of(30.minutes.from_now)
        expect(job.send(:parse_event_time, 'in 2 hours')).to be_within(1.minute).of(2.hours.from_now)
        expect(job.send(:parse_event_time, 'tonight')).to be_within(1.hour).of(Time.now.end_of_day.change(hour: 21))
        expect(job.send(:parse_event_time, 'tomorrow')).to be_within(1.hour).of(Time.now.tomorrow.change(hour: 20))
      end

      it 'handles nil and blank strings', :vcr do
        expect(job.send(:parse_event_time, nil)).to be_nil
        expect(job.send(:parse_event_time, '')).to be_nil
      end
    end

    describe '#store_memories' do
      it 'avoids storing duplicate memories', :vcr do
        memory_data = {
          content: 'Test memory',
          data: { emotional_intensity: 0.5 }
        }

        # Simulate existing similar memory
        allow(Memory).to receive(:where).and_return(double(exists?: true))
        expect(Memory).not_to receive(:create!)

        job.send(:store_memories, [memory_data])
      end

      it 'stores unique memories', :vcr do
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
