# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/openrouter_service'

RSpec.describe OpenRouterService, 'Integration with Model Presets' do
  let(:mock_response) do
    {
      'choices' => [
        {
          'message' => {
            'content' => 'Test response from AI model'
          }
        }
      ]
    }
  end

  before do
    # Reset all cached instance variables before each test
    described_class.instance_variable_set(:@client, nil)
    described_class.instance_variable_set(:@request_handler, nil)
    described_class.clear_cache!
  end

  # Helper method to stub the client for specific tests
  def stub_openrouter_client
    mock_client = instance_double(OpenRouter::Client)
    # Instead of stubbing the class, stub the instance variable
    described_class.instance_variable_set(:@client, mock_client)
    mock_client
  end

  describe 'blacklist validation' do
    it 'prevents using expensive models', :vcr do
      expect do
        described_class.complete('Test', model: 'openai/o1-pro')
      end.to raise_error(ArgumentError, /blacklisted due to high cost/)
    end

    it 'allows safe models', :vcr do
      mock_client = stub_openrouter_client
      expect(mock_client).to receive(:complete).and_return(mock_response)

      result = described_class.complete('Test', model: 'meta-llama/llama-3.2-3b-instruct')
      expect(result).to eq(mock_response)
    end
  end

  describe 'convenience methods' do
    it 'complete_cheap uses small_cheapest preset', :vcr do
      mock_client = stub_openrouter_client
      expect(mock_client).to receive(:complete).with(
        [{ role: 'user', content: 'Test prompt' }],
        model: 'meta-llama/llama-3.2-3b-instruct',
        extras: {
          max_tokens: 1000,
          temperature: 0.7
        }
      ).and_return(mock_response)

      described_class.complete_cheap('Test prompt')
    end

    it 'complete_conversation uses conversation_small preset', :vcr do
      mock_client = stub_openrouter_client
      expect(mock_client).to receive(:complete).with(
        [{ role: 'user', content: 'Test prompt' }],
        model: 'qwen/qwen3-235b-a22b-thinking-2507',
        extras: {
          max_tokens: 1000,
          temperature: 0.7
        }
      ).and_return(mock_response)

      described_class.complete_conversation('Test prompt')
    end

    it 'analyze_image uses image_classification preset', :vcr do
      mock_client = stub_openrouter_client
      expect(mock_client).to receive(:complete).with(
        [{ role: 'user', content: 'Analyze this image' }],
        model: 'qwen/qwen2.5-vl-72b-instruct:free',
        extras: {
          max_tokens: 1000,
          temperature: 0.7
        }
      ).and_return(mock_response)

      described_class.analyze_image('Analyze this image')
    end
  end

  describe 'preset integration' do
    it 'validates all preset models are not blacklisted', :vcr do
      GlitchCube::ModelPresets.preset_names.each do |preset_name|
        model = GlitchCube::ModelPresets.get_model(preset_name)
        expect(GlitchCube::ModelPresets.blacklisted?(model)).to be(false),
                                                                "Preset #{preset_name} uses blacklisted model: #{model}"
      end
    end
  end
end
