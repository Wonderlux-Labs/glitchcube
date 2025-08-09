# frozen_string_literal: true

require 'spec_helper'

RSpec.describe DisplayTool do
  describe 'tool interface' do
    it 'has required metadata methods' do
      expect(described_class).to respond_to(:available_tools)
      expect(described_class).to respond_to(:prompt_description)
      expect(described_class).to respond_to(:tool_schemas)
    end

    it 'lists the correct available tools' do
      tools = described_class.available_tools
      expect(tools).to be_an(Array)
      expect(tools).to include('display_text', 'send_notification', 'set_mood_light', 'clear_display')
    end

    it 'has schemas for all available tools' do
      schemas = described_class.tool_schemas
      described_class.available_tools.each do |tool|
        expect(schemas).to have_key(tool)
      end
    end
  end

  describe 'method signatures' do
    describe '.display_text' do
      it 'responds to display_text' do
        expect(described_class).to respond_to(:display_text)
      end

      it 'has correct schema definition' do
        schema = described_class.tool_schemas['display_text']
        expect(schema['type']).to eq('object')
        expect(schema['properties']).to have_key('text')
        expect(schema['properties']).to have_key('rainbow')
        expect(schema['properties']).to have_key('icon')
        expect(schema['properties']).to have_key('duration')
        expect(schema['required']).to eq(['text'])
      end

      it 'requires text parameter' do
        schema = described_class.tool_schemas['display_text']
        expect(schema['required']).to include('text')
        expect(schema['properties']['text']['type']).to eq('string')
      end
    end

    describe '.send_notification' do
      it 'responds to send_notification' do
        expect(described_class).to respond_to(:send_notification)
      end

      it 'has correct schema definition' do
        schema = described_class.tool_schemas['send_notification']
        expect(schema['type']).to eq('object')
        expect(schema['properties']).to have_key('message')
        expect(schema['properties']).to have_key('icon')
        expect(schema['properties']).to have_key('sound')
        expect(schema['required']).to eq(['message'])
      end

      it 'defines valid sound options' do
        schema = described_class.tool_schemas['send_notification']
        sound_enum = schema['properties']['sound']['enum']
        expect(sound_enum).to include('beep', 'alarm', 'notification')
      end
    end

    describe '.set_mood_light' do
      it 'responds to set_mood_light' do
        expect(described_class).to respond_to(:set_mood_light)
      end

      it 'has correct schema definition' do
        schema = described_class.tool_schemas['set_mood_light']
        expect(schema['type']).to eq('object')
        expect(schema['properties']).to have_key('rgb')
        expect(schema['properties']).to have_key('brightness')
        expect(schema['required']).to eq(%w[rgb brightness])
      end

      it 'defines rgb as array of integers' do
        schema = described_class.tool_schemas['set_mood_light']
        rgb_prop = schema['properties']['rgb']
        expect(rgb_prop['type']).to eq('array')
        expect(rgb_prop['items']['type']).to eq('integer')
        expect(rgb_prop['items']['minimum']).to eq(0)
        expect(rgb_prop['items']['maximum']).to eq(255)
      end

      it 'defines brightness with constraints' do
        schema = described_class.tool_schemas['set_mood_light']
        brightness_prop = schema['properties']['brightness']
        expect(brightness_prop['type']).to eq('integer')
        expect(brightness_prop['minimum']).to eq(0)
        expect(brightness_prop['maximum']).to eq(100)
      end
    end

    describe '.clear_display' do
      it 'responds to clear_display' do
        expect(described_class).to respond_to(:clear_display)
      end

      it 'has correct schema definition' do
        schema = described_class.tool_schemas['clear_display']
        expect(schema['type']).to eq('object')
        expect(schema['properties']).to eq({})
      end
    end
  end

  describe 'constants' do
    it 'has AWTRIX_DEVICE constant' do
      expect(described_class::AWTRIX_DEVICE).to eq('awtrix_bedroom')
    end

    it 'has AWTRIX_MATRIX_LIGHT constant' do
      expect(described_class::AWTRIX_MATRIX_LIGHT).to eq('light.awtrix_b85e20_matrix')
    end

    it 'has ICONS constant with common icons' do
      expect(described_class::ICONS).to be_a(Hash)
      expect(described_class::ICONS).to have_key('warning')
      expect(described_class::ICONS).to have_key('info')
      expect(described_class::ICONS).to have_key('success')
    end

    it 'has SOUNDS constant' do
      expect(described_class::SOUNDS).to eq(%w[beep alarm notification])
    end
  end
end
