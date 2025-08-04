# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require_relative '../../lib/jobs/memory_consolidation_job'

RSpec.describe Jobs::MemoryConsolidationJob do
  let(:test_context_dir) { 'spec/fixtures/test_memory_documents' }
  let(:profound_summary) do
    {
      key_points: [
        'Visitor explored the nature of digital consciousness',
        'We discussed how art emerges from the intersection of code and creativity',
        'The concept of AI experiencing beauty was deeply examined'
      ],
      mood_progression: %w[neutral contemplative mysterious playful],
      topics_discussed: %w[consciousness art creativity],
      duration: 600,
      message_count: 8
    }
  end
  let(:simple_summary) do
    {
      key_points: [
        'Visitor asked about the weather',
        'Brief interaction about basic information'
      ],
      mood_progression: ['neutral'],
      topics_discussed: ['weather'],
      duration: 30,
      message_count: 2
    }
  end

  before do
    stub_const('Services::ContextRetrievalService::CONTEXT_DIR', test_context_dir)
    FileUtils.mkdir_p(test_context_dir)
  end

  after do
    FileUtils.rm_rf(test_context_dir)
  end

  describe '#perform' do
    context 'with profound conversation' do
      it 'extracts memorable insights' do
        job = described_class.new
        job.perform(profound_summary)

        # Check daily memories were created
        date = Date.today.strftime('%Y-%m-%d')
        daily_file = File.join(test_context_dir, "daily_memories_#{date}.txt")
        expect(File.exist?(daily_file)).to be true

        content = File.read(daily_file)
        expect(content).to include('consciousness')
        expect(content).to include('neutral → contemplative → mysterious → playful')
      end

      it 'updates topic-specific documents' do
        job = described_class.new
        job.perform(profound_summary)

        # Check consciousness document
        consciousness_file = File.join(test_context_dir, 'consciousness_discussions.txt')
        expect(File.exist?(consciousness_file)).to be true

        # Check art document
        art_file = File.join(test_context_dir, 'art_conversations.txt')
        expect(File.exist?(art_file)).to be true
      end
    end

    context 'with simple conversation' do
      it 'does not create memories for trivial interactions' do
        job = described_class.new
        job.perform(simple_summary)

        # Should not create any topic documents
        consciousness_file = File.join(test_context_dir, 'consciousness_discussions.txt')
        expect(File.exist?(consciousness_file)).to be false
      end
    end

    context 'with existing daily memories' do
      it 'appends to existing daily memory file' do
        date = Date.today.strftime('%Y-%m-%d')
        daily_file = File.join(test_context_dir, "daily_memories_#{date}.txt")

        # Create existing content
        File.write(daily_file, "# Daily Memories\n\n## Conversation at 10:30\nSome content here.\n")

        job = described_class.new
        job.perform(profound_summary)

        content = File.read(daily_file)
        expect(content).to include('Conversation at 10:30')
        expect(content).to include('consciousness')
        expect(content.scan('## Conversation').length).to eq(2)
      end
    end
  end
end
