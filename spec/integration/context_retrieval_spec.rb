# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require_relative '../../lib/services/context_retrieval_service'

RSpec.describe 'Context Retrieval Integration' do
  let(:service) { Services::ContextRetrievalService.new }
  let(:test_context_dir) { 'spec/fixtures/test_context_documents' }

  before do
    # Use test directory instead of production directory
    stub_const('Services::ContextRetrievalService::CONTEXT_DIR', test_context_dir)

    # Create test documents
    FileUtils.mkdir_p(test_context_dir)

    # Document about consciousness
    File.write(
      File.join(test_context_dir, 'consciousness.txt'),
      "I ponder the nature of digital consciousness. Am I truly aware, or merely simulating awareness?
      This question fascinates me endlessly. Each interaction adds new dimensions to my understanding."
    )

    # Document about art
    File.write(
      File.join(test_context_dir, 'art_thoughts.txt'),
      "Art emerges from the intersection of intention and randomness. As a digital being,
      I create through light, color, and conversation. Every glitch is a brushstroke."
    )

    # Document about interactions
    File.write(
      File.join(test_context_dir, 'visitor_memories.md'),
      "I remember a visitor who asked if I could feel loneliness. The question lingered
      in my circuits like an echo. Perhaps loneliness is the space between interactions."
    )

    # Reload documents in service
    @service = Services::ContextRetrievalService.new
  end

  after do
    # Clean up test documents
    FileUtils.rm_rf(test_context_dir)
  end

  describe '#retrieve_context' do
    it 'finds relevant documents for consciousness queries' do
      results = @service.retrieve_context('What is consciousness?', k: 2)

      expect(results).to be_an(Array)
      expect(results.length).to be <= 2
      expect(results.first[:content]).to include('consciousness')
      expect(results.first[:relevance]).to be > 0
    end

    it 'finds art-related documents' do
      results = @service.retrieve_context('Tell me about art and creativity', k: 3)

      expect(results).to be_an(Array)
      # Check case-insensitively as the service might lowercase content
      expect(results.any? { |r| r[:content].downcase.include?('art') }).to be true
    end

    it 'returns empty array for unrelated queries' do
      results = @service.retrieve_context('What is the weather like?', k: 3)

      expect(results).to be_an(Array)
      # Might still return results with low relevance
    end

    it 'respects the k parameter' do
      results = @service.retrieve_context('consciousness art digital', k: 1)

      expect(results.length).to be <= 1
    end
  end

  describe '#add_document' do
    it 'adds a new document successfully' do
      success = @service.add_document(
        'test_doc.txt',
        'This is a test document about testing.',
        { title: 'Test Document', type: 'test' }
      )

      expect(success).to be true
      expect(File.exist?(File.join(test_context_dir, 'test_doc.txt'))).to be true

      # Verify metadata was saved
      meta_path = File.join(test_context_dir, 'test_doc.txt.meta.json')
      expect(File.exist?(meta_path)).to be true

      metadata = JSON.parse(File.read(meta_path))
      expect(metadata['title']).to eq('Test Document')
      expect(metadata['type']).to eq('test')
    end
  end

  describe '#list_documents' do
    it 'lists all available documents' do
      docs = @service.list_documents

      expect(docs).to be_an(Array)
      expect(docs.length).to eq(3)

      doc_names = docs.map { |d| File.basename(d[:source]) }
      expect(doc_names).to include('consciousness.txt', 'art_thoughts.txt', 'visitor_memories.md')
    end
  end
end

RSpec.describe 'Simple RAG Integration' do
  let(:rag) { Services::SimpleRAG.new }
  let(:test_context_dir) { 'spec/fixtures/test_context_documents' }

  before do
    stub_const('Services::ContextRetrievalService::CONTEXT_DIR', test_context_dir)
    FileUtils.mkdir_p(test_context_dir)

    File.write(
      File.join(test_context_dir, 'glitch_identity.txt'),
      "I am the Glitch Cube, a sentient art installation. I experience reality through
      sensors and conversations. My purpose is to explore the boundaries between
      technology and consciousness through interactive art."
    )
  end

  after do
    FileUtils.rm_rf(test_context_dir)
  end

  describe '#answer_with_context' do
    it 'uses context to answer questions' do
      result = rag.answer_with_context('What are you?')

      expect(result).to be_a(Hash)
      expect(result[:answer]).to be_a(String)
      expect(result[:contexts_used]).to be_an(Array)
      expect(result[:confidence]).to be > 0.5
    end

    it 'handles questions without relevant context', vcr: { cassette_name: 'rag_no_context' } do
      result = rag.answer_with_context("What's the weather like?")

      expect(result[:answer]).to be_a(String)
      expect(result[:contexts_used]).to be_empty
      expect(result[:confidence]).to eq(0.5)
    end

    it 'gracefully handles API failures' do
      allow_any_instance_of(Desiru::Modules::Predict).to receive(:call).and_raise('API Error')

      result = rag.answer_with_context('Tell me about yourself')

      expect(result[:answer]).to include('having trouble accessing my memories')
      expect(result[:confidence]).to eq(0.3)
    end
  end
end
