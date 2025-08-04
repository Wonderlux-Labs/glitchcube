require 'spec_helper'
require_relative '../../config/model_presets'

RSpec.describe GlitchCube::ModelPresets do
  describe '.get_model' do
    it 'returns primary model for conversation_small preset' do
      model = described_class.get_model(:conversation_small)
      expect(model).to eq('qwen/qwen3-235b-a22b-thinking-2507')
    end

    it 'returns alternative model when fallback_index specified' do
      model = described_class.get_model(:conversation_small, fallback_index: 1)
      expect(model).to eq('deepseek/deepseek-r1-distill-qwen-32b')
    end

    it 'returns primary model when fallback_index out of range' do
      model = described_class.get_model(:conversation_small, fallback_index: 10)
      expect(model).to eq('qwen/qwen3-235b-a22b-thinking-2507')
    end

    it 'handles string preset names' do
      model = described_class.get_model('small_cheapest')
      expect(model).to eq('meta-llama/llama-3.2-3b-instruct')
    end
  end

  describe '.blacklisted?' do
    it 'identifies expensive models as blacklisted' do
      expect(described_class.blacklisted?('openai/o1-pro')).to be true
    end

    it 'allows safe models' do
      expect(described_class.blacklisted?('meta-llama/llama-3.2-3b-instruct')).to be false
    end
  end

  describe '.validate_model!' do
    it 'raises error for blacklisted models' do
      expect {
        described_class.validate_model!('openai/o1-pro')
      }.to raise_error(ArgumentError, /blacklisted due to high cost/)
    end

    it 'returns model_id for safe models' do
      result = described_class.validate_model!('meta-llama/llama-3.2-3b-instruct')
      expect(result).to eq('meta-llama/llama-3.2-3b-instruct')
    end
  end

  describe '.preset_names' do
    it 'returns available preset categories' do
      names = described_class.preset_names
      expect(names).to include(:SMALL_CHEAPEST, :CONVERSATION_SMALL, :IMAGE_CLASSIFICATION)
      expect(names).not_to include(:FREE_MODELS, :BLACKLISTED_EXPENSIVE)
    end
  end

  describe 'preset structure validation' do
    it 'ensures all presets have required structure' do
      described_class.preset_names.each do |preset_name|
        preset = described_class.const_get(preset_name)
        
        expect(preset).to have_key(:primary)
        expect(preset[:primary]).to be_a(String)
        expect(preset[:primary]).not_to be_empty
        
        if preset[:alternatives]
          expect(preset[:alternatives]).to be_an(Array)
          preset[:alternatives].each do |alt|
            expect(alt).to be_a(String)
            expect(alt).not_to be_empty
          end
        end
      end
    end
  end

  describe 'cost safety' do
    it 'ensures no blacklisted models appear in presets' do
      dangerous_models = described_class::BLACKLISTED_EXPENSIVE
      
      described_class.preset_names.each do |preset_name|
        preset = described_class.const_get(preset_name)
        
        # Check primary model
        expect(dangerous_models).not_to include(preset[:primary])
        
        # Check alternatives
        if preset[:alternatives]
          preset[:alternatives].each do |alt|
            expect(dangerous_models).not_to include(alt)
          end
        end
      end
    end
  end
end