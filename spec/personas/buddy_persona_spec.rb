# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Personas::BuddyPersona do
  let(:persona) { described_class.new }

  describe '#name' do
    it 'returns buddy' do
      expect(persona.name).to eq('buddy')
    end
  end

  describe '#prompt_file' do
    it 'returns buddy.txt' do
      expect(persona.prompt_file).to eq('buddy.txt')
    end
  end

  describe '#available_tools' do
    it 'returns SpeechTool and LightingTool' do
      expect(persona.available_tools).to eq([SpeechTool, LightingTool])
    end
  end

  describe '#fallback_responses' do
    it 'returns array of enthusiastic responses with profanity' do
      responses = persona.fallback_responses
      expect(responses).to be_an(Array)
      expect(responses).not_to be_empty
      expect(responses.any? { |r| r.include?('fuck') || r.include?('shit') }).to be true
    end
  end

  describe '#offline_responses' do
    it 'returns array of offline responses with profanity' do
      responses = persona.offline_responses
      expect(responses).to be_an(Array)
      expect(responses).not_to be_empty
      expect(responses.any? { |r| r.include?('fuck') || r.include?('shit') }).to be true
    end
  end

  describe '#generate_fallback_response' do
    it 'returns a random fallback response' do
      response = persona.generate_fallback_response
      expect(persona.fallback_responses).to include(response)
    end
  end

  describe '#generate_offline_response' do
    it 'returns an offline response with encouragement' do
      response = persona.generate_offline_response
      expect(response).to be_a(String)
      expect(response).not_to be_empty
    end
  end

  describe '#tool_schemas' do
    it 'returns OpenAI function schemas for available tools' do
      schemas = persona.tool_schemas
      expect(schemas).to be_an(Array)
      expect(schemas.size).to be > 0

      schemas.each do |schema|
        expect(schema['type']).to eq('function')
        expect(schema['function']).to have_key('name')
        expect(schema['function']).to have_key('description')
        expect(schema['function']).to have_key('parameters')
      end
    end
  end

  describe '#generate_system_prompt' do
    it 'generates a system prompt with all sections' do
      prompt = persona.generate_system_prompt
      expect(prompt).to include('CURRENT DATE AND TIME:')
      expect(prompt).to include('AVAILABLE TOOLS AND CAPABILITIES:')
    end
  end
end
