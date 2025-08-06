# frozen_string_literal: true

require 'spec_helper'
require_relative '../../app/models/memory'

RSpec.describe Memory do
  describe 'JSONB storage flexibility' do
    it 'stores and retrieves basic memory content' do
      memory = described_class.create!(
        content: 'Someone tried to STEAL me!',
        data: {}
      )
      expect(memory.content).to eq('Someone tried to STEAL me!')
    end

    it 'stores any data structure in JSONB' do
      memory = described_class.create!(
        content: 'Test memory',
        data: {
          anything: 'goes here',
          nested: { stuff: 'works' },
          arrays: %w[also work],
          numbers: 42
        }
      )
      expect(memory.data['anything']).to eq('goes here')
      expect(memory.data['nested']['stuff']).to eq('works')
    end
  end

  describe 'helper methods' do
    let(:memory) { described_class.new(content: 'Test') }

    it 'provides convenient setters and getters' do
      memory.location = 'The Man'
      memory.tags = %w[wild funny]
      memory.people = %w[Doug Rainbow]
      memory.emotional_intensity = 0.8

      expect(memory.location).to eq('The Man')
      expect(memory.tags).to eq(%w[wild funny])
      expect(memory.people).to eq(%w[Doug Rainbow])
      expect(memory.emotional_intensity).to eq(0.8)
    end

    it 'stores coordinates' do
      memory.coordinates = { lat: 40.7864, lng: -119.2065 }
      expect(memory.coordinates).to eq({ lat: 40.7864, lng: -119.2065 })
    end

    it 'handles event times' do
      future_time = 1.day.from_now
      memory.event_time = future_time
      expect(memory.event_time).to be_within(1.second).of(future_time)
      expect(memory.upcoming_event?).to be true
    end

    it 'allows custom data fields' do
      memory.add_data('weather', 'dusty')
      memory.add_data('mood', 'playful')

      expect(memory.get_data('weather')).to eq('dusty')
      expect(memory.get_data('mood')).to eq('playful')
    end
  end

  describe 'scopes' do
    before do
      described_class.create!(content: 'High intensity', data: { emotional_intensity: 0.9, location: 'The Man', tags: ['wild'] })
      described_class.create!(content: 'Medium intensity', data: { emotional_intensity: 0.5, location: 'Center Camp', tags: ['chill'] })
      described_class.create!(content: 'Low intensity', data: { emotional_intensity: 0.2, location: 'The Man', tags: ['boring'] })
    end

    it 'filters by intensity' do
      expect(described_class.high_intensity.count).to eq(1)
      expect(described_class.medium_intensity.count).to eq(1)
    end

    it 'filters by location' do
      expect(described_class.by_location('The Man').count).to eq(2)
      expect(described_class.by_location('Center Camp').count).to eq(1)
    end

    it 'filters by tags' do
      expect(described_class.tagged_with('wild').count).to eq(1)
      expect(described_class.tagged_with_any(%w[wild chill]).count).to eq(2)
    end
  end

  describe '#story_value' do
    it 'calculates default story value' do
      memory = described_class.create!(
        content: 'Test',
        data: { emotional_intensity: 0.8 }
      )
      expect(memory.story_value).to be_between(0, 1)
    end

    it 'uses experimental algorithm when specified' do
      memory = described_class.create!(
        content: 'Test',
        data: {
          emotional_intensity: 0.8,
          scoring_algorithm: 'experimental',
          score_config: {
            intensity_weight: 0.9,
            freshness_weight: 0.05,
            recency_weight: 0.05
          }
        }
      )
      expect(memory.story_value).to be_between(0, 1)
    end
  end

  describe '#recall!' do
    it 'tracks when memory is recalled' do
      memory = described_class.create!(content: 'Test', data: {})
      expect(memory.recall_count).to eq(0)

      memory.recall!
      expect(memory.recall_count).to eq(1)
      expect(memory.last_recalled_at).to be_present
    end
  end

  describe '#to_conversation_context' do
    it 'formats regular memories' do
      memory = described_class.create!(
        content: 'Someone stole me',
        data: {
          location: 'The Man',
          people: ['Crazy Dave']
        }
      )

      context = memory.to_conversation_context
      expect(context).to include('The Man')
      expect(context).to include('Someone stole me')
      expect(context).to include('Crazy Dave')
    end

    it 'formats upcoming events' do
      memory = described_class.create!(
        content: 'Robot Heart sunrise',
        data: {
          event_name: 'Robot Heart',
          event_time: (Time.now + 25.hours).iso8601, # Ensure it's within the "Tomorrow" range
          location: 'Deep Playa'
        }
      )

      context = memory.to_conversation_context
      expect(context).to include('Robot Heart')
      expect(context).to include('Tomorrow')
      expect(context).to include('Deep Playa')
    end
  end
end
