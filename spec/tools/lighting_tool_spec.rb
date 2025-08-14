# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Tools::LightingTool do
  describe 'tool interface' do
    it 'has required metadata methods' do
      expect(described_class).to respond_to(:available_tools)
      expect(described_class).to respond_to(:prompt_description)
      expect(described_class).to respond_to(:tool_schemas)
    end

    it 'lists the correct available tools' do
      tools = described_class.available_tools
      expect(tools).to be_an(Array)
      expect(tools).to include('set_state', 'get_state', 'list_states')
    end

    it 'has schemas for all available tools' do
      schemas = described_class.tool_schemas
      described_class.available_tools.each do |tool|
        expect(schemas).to have_key(tool)
      end
    end
  end

  describe 'method signatures' do
    describe '.set_state' do
      it 'responds to set_state with expected parameters' do
        expect(described_class).to respond_to(:set_state)
      end

      it 'has correct schema definition' do
        schema = described_class.tool_schemas['set_state']
        expect(schema['type']).to eq('object')
        expect(schema['properties']).to have_key('state')
        expect(schema['properties']).to have_key('target')
        expect(schema['properties']).to have_key('color')
        expect(schema['properties']).to have_key('brightness')
        expect(schema['properties']).not_to have_key('effect') # Effect is handled by separate set_effect method
        expect(schema['required']).to eq(['state'])
      end
    end

    describe '.get_state' do
      it 'responds to get_state' do
        expect(described_class).to respond_to(:get_state)
      end

      it 'has correct schema definition' do
        schema = described_class.tool_schemas['get_state']
        expect(schema['type']).to eq('object')
        expect(schema['properties']).to have_key('target')
      end
    end

    describe '.list_states' do
      it 'responds to list_states' do
        expect(described_class).to respond_to(:list_states)
      end

      it 'has correct schema definition' do
        schema = described_class.tool_schemas['list_states']
        expect(schema['type']).to eq('object')
        expect(schema['properties']).to eq({})
      end
    end
  end

  describe 'schema validations' do
    it 'defines valid enum values for state' do
      schema = described_class.tool_schemas['set_state']
      state_enum = schema['properties']['state']['enum']
      expect(state_enum).to include('on', 'off')
    end

    it 'defines valid enum values for targets' do
      schema = described_class.tool_schemas['set_state']
      target_enum = schema['properties']['target']['enum']
      expect(target_enum).to include('cube', 'cart', 'voice_ring', 'matrix', 'indicators', 'all')
    end

    it 'has separate set_effect method schema' do
      schema = described_class.tool_schemas['set_effect']
      expect(schema).to be_present
      expect(schema['properties']).to have_key('entity_id')
      expect(schema['properties']).to have_key('effect')
    end

    it 'defines brightness as integer with constraints' do
      schema = described_class.tool_schemas['set_state']
      brightness = schema['properties']['brightness']
      expect(brightness['type']).to eq('integer')
      expect(brightness['minimum']).to eq(0)
      expect(brightness['maximum']).to eq(255)
    end
  end
end
