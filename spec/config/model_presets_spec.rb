# frozen_string_literal: true

require 'spec_helper'
require_relative '../../config/model_presets'

RSpec.describe GlitchCube::ModelPresets do
  describe '.get_model' do
    it 'returns primary model for conversation preset' do
      model = described_class.get_model(:conversation)
      expect(model).to be_a(String)
      expect(model).not_to be_empty
    end

    it 'returns model for cheap_tools preset' do
      model = described_class.get_model(:cheap_tools)
      expect(model).to be_a(String)
      expect(model).not_to be_empty
    end

    it 'returns default model when no type provided' do
      model = described_class.get_model
      expect(model).to eq(described_class::DEFAULT_MODEL)
    end

    it 'raises error for invalid preset names' do
      expect { described_class.get_model(:invalid_preset) }
        .to raise_error(ArgumentError, /Invalid model type/)
    end
  end

  describe '.blacklisted?' do
    it 'identifies expensive models as blacklisted' do
      expect(described_class.blacklisted?('openai/o1-pro')).to be true
    end

    it 'allows safe models' do
      expect(described_class.blacklisted?('meta-llama/llama-3.2-1b-instruct')).to be false
    end
  end

  describe '.validate_model!' do
    it 'raises error for blacklisted models' do
      expect do
        described_class.validate_model!('openai/o1-pro')
      end.to raise_error(ArgumentError, /blacklisted due to high cost/)
    end

    it 'returns model_id for safe models' do
      result = described_class.validate_model!('meta-llama/llama-3.2-1b-instruct')
      expect(result).to eq('meta-llama/llama-3.2-1b-instruct')
    end
  end

  describe '.preset_types' do
    it 'returns available preset categories' do
      types = described_class.preset_types
      expect(types).to be_an(Array)
      expect(types).to include(:conversation)
      expect(types).to include(:free)
      expect(types).to include(:premium)
    end
  end

  describe 'blacklisted models safety' do
    it 'ensures no blacklisted models are returned by get_model' do
      described_class.preset_types.each do |preset_type|
        model = described_class.get_model(preset_type)
        expect(described_class.blacklisted?(model)).to be false
      end
    end
  end
end
