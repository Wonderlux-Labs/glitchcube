# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/tools/speech_tool'

RSpec.describe SpeechTool do
  describe 'tool interface' do
    it 'has required metadata methods' do
      expect(described_class).to respond_to(:available_tools)
      expect(described_class).to respond_to(:prompt_description)
      expect(described_class).to respond_to(:tool_schemas)
    end

    it 'lists the correct available tools' do
      tools = described_class.available_tools
      expect(tools).to be_an(Array)
      expect(tools).to include('speak_text', 'get_tts_status')
    end

    it 'has schemas for all available tools' do
      schemas = described_class.tool_schemas
      described_class.available_tools.each do |tool|
        expect(schemas).to have_key(tool)
      end
    end
  end

  describe 'method signatures' do
    describe '.speak_text' do
      it 'responds to speak_text with expected parameters' do
        expect(described_class).to respond_to(:speak_text)
      end

      it 'has correct schema definition' do
        schema = described_class.tool_schemas['speak_text']
        expect(schema['type']).to eq('object')
        expect(schema['properties']).to have_key('text')
        expect(schema['properties']).to have_key('entity_id')
        expect(schema['properties']).to have_key('language')
        expect(schema['properties']).to have_key('voice')
        expect(schema['required']).to eq(['text'])
      end

      it 'requires text parameter' do
        schema = described_class.tool_schemas['speak_text']
        expect(schema['required']).to include('text')
        expect(schema['properties']['text']['type']).to eq('string')
      end
    end

    describe '.get_tts_status' do
      it 'responds to get_tts_status' do
        expect(described_class).to respond_to(:get_tts_status)
      end

      it 'has correct schema definition' do
        schema = described_class.tool_schemas['get_tts_status']
        expect(schema['type']).to eq('object')
        expect(schema['properties']).to have_key('entity_id')
      end

      it 'entity_id is optional' do
        schema = described_class.tool_schemas['get_tts_status']
        expect(schema['required'] || []).to be_empty
      end
    end
  end

  describe 'default values' do
    it 'has a DEFAULT_ENTITY constant' do
      expect(described_class::DEFAULT_ENTITY).to eq('media_player.square_voice')
    end
  end
end
