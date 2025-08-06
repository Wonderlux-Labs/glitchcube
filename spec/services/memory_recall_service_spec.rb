# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/memory_recall_service'

RSpec.describe Services::MemoryRecallService do
  describe '.get_relevant_memories' do
    before do
      # Create test memories
      @upcoming_event = Memory.create!(
        content: 'Robot Heart sunrise tomorrow!',
        data: {
          event_time: 1.day.from_now.iso8601,
          emotional_intensity: 0.8
        }
      )

      @location_memory = Memory.create!(
        content: 'Someone covered me in glitter here',
        data: {
          location: '9 & K',
          emotional_intensity: 0.6
        }
      )

      @high_intensity = Memory.create!(
        content: 'THE TEMPLE BURN WAS AMAZING',
        data: {
          emotional_intensity: 1.0,
          location: 'The Temple'
        }
      )
    end

    it 'prioritizes upcoming events' do
      memories = described_class.get_relevant_memories
      expect(memories.first).to eq(@upcoming_event)
    end

    it 'includes location-based memories when location provided' do
      memories = described_class.get_relevant_memories(location: '9 & K')
      expect(memories).to include(@location_memory)
    end

    it 'fills remaining slots with high-intensity memories' do
      memories = described_class.get_relevant_memories(limit: 3)
      expect(memories).to include(@high_intensity)
    end

    it 'tracks recall count' do
      expect do
        described_class.get_relevant_memories
      end.to change { @upcoming_event.reload.recall_count }.by(1)
    end

    it 'limits results to specified count' do
      5.times do |i|
        Memory.create!(
          content: "Memory #{i}",
          data: { emotional_intensity: 0.9 }
        )
      end

      memories = described_class.get_relevant_memories(limit: 2)
      expect(memories.size).to eq(2)
    end
  end

  describe '.format_for_context' do
    it 'formats memories with introductions' do
      memories = [
        Memory.new(content: 'Test memory', data: { tags: ['wild'] })
      ]

      formatted = described_class.format_for_context(memories)
      expect(formatted).to include('RECENT MEMORIES')
      expect(formatted).to include('Test memory')
    end

    it 'returns empty string for no memories' do
      expect(described_class.format_for_context([])).to eq('')
    end
  end

  describe '.know_person?' do
    before do
      Memory.create!(
        content: 'Met Doug at Center Camp',
        data: { people: ['Doug'] }
      )
    end

    it 'returns true if person is known' do
      expect(described_class.know_person?('Doug')).to be true
    end

    it 'returns false if person is unknown' do
      expect(described_class.know_person?('Unknown Person')).to be false
    end
  end

  describe '.person_summary' do
    before do
      Memory.create!(
        content: 'Doug told me about the art car',
        data: {
          people: ['Doug'],
          location: 'Center Camp',
          tags: %w[art-car conversation],
          emotional_intensity: 0.7
        }
      )

      Memory.create!(
        content: 'Doug brought me water',
        data: {
          people: %w[Doug Rainbow],
          location: 'The Man',
          tags: %w[kindness water],
          emotional_intensity: 0.9
        }
      )
    end

    it 'returns person summary with best story' do
      summary = described_class.person_summary('Doug')

      expect(summary[:name]).to eq('Doug')
      expect(summary[:encounter_count]).to eq(2)
      expect(summary[:locations]).to include('Center Camp', 'The Man')
      expect(summary[:vibe_tags]).to include('kindness', 'water', 'art-car', 'conversation')
      expect(summary[:best_story]).to include('water') # Higher intensity story
    end

    it 'returns nil for unknown person' do
      expect(described_class.person_summary('Unknown')).to be_nil
    end
  end

  describe '.get_social_connections' do
    before do
      Memory.create!(
        content: 'Doug and Rainbow visited',
        data: {
          people: %w[Doug Rainbow],
          tags: ['social']
        }
      )

      Memory.create!(
        content: 'Doug came with Sparkle',
        data: {
          people: %w[Doug Sparkle],
          tags: ['friends']
        }
      )
    end

    it 'finds co-mentioned people' do
      connections = described_class.get_social_connections('Doug')

      expect(connections[:name]).to eq('Doug')
      expect(connections[:mentioned_count]).to eq(2)
      expect(connections[:co_mentioned]).to include('Rainbow', 'Sparkle')
    end
  end

  describe '.get_trending_memories' do
    before do
      # Create recent high-intensity memory
      Memory.create!(
        content: 'Amazing art car parade!',
        data: { emotional_intensity: 0.9 },
        created_at: 2.hours.ago
      )

      # Create old memory
      Memory.create!(
        content: 'Old story',
        data: { emotional_intensity: 0.9 },
        created_at: 2.days.ago
      )
    end

    it 'returns recent high-intensity fresh memories' do
      trending = described_class.get_trending_memories
      expect(trending.first.content).to include('art car parade')
    end
  end
end
