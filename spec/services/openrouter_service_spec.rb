# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/openrouter_service'

RSpec.describe OpenRouterService do
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
    # Reset service state between tests
    described_class.clear_cache!
    # Clear the memoized client and request handler
    described_class.instance_variable_set(:@client, nil)
    described_class.instance_variable_set(:@request_handler, nil)
  end

  # Helper to stub the client instance variable
  def stub_client_with_mock
    mock_client = instance_double(OpenRouter::Client)
    described_class.instance_variable_set(:@client, mock_client)
    mock_client
  end

  describe '.complete' do
    it 'makes a simple completion request', :vcr do
      mock_client = stub_client_with_mock

      expect(mock_client).to receive(:complete).with(
        [{ role: 'user', content: 'Test prompt' }],
        model: 'google/gemini-2.5-flash',
        extras: {
          max_tokens: 1000,
          temperature: 0.7
        }
      ).and_return(mock_response)

      result = described_class.complete('Test prompt')
      expect(result).to eq(mock_response)
    end

    it 'accepts custom options', :vcr do
      mock_client = stub_client_with_mock

      expect(mock_client).to receive(:complete).with(
        [{ role: 'user', content: 'Test prompt' }],
        model: 'different-model',
        extras: {
          max_tokens: 100,
          temperature: 0.3
        }
      ).and_return(mock_response)

      result = described_class.complete('Test prompt',
                                        model: 'different-model',
                                        max_tokens: 100,
                                        temperature: 0.3)
      expect(result).to eq(mock_response)
    end

    it 'raises error for blacklisted models', :vcr do
      expect do
        described_class.complete('Test prompt', model: 'openai/o1-pro')
      end.to raise_error(ArgumentError, /blacklisted due to high cost/)
    end
  end

  describe '.complete_with_context' do
    it 'handles string messages', :vcr do
      mock_client = stub_client_with_mock
      expect(mock_client).to receive(:complete).with(
        [{ role: 'user', content: 'Simple string' }],
        model: 'google/gemini-2.5-flash',
        extras: {
          max_tokens: 1000,
          temperature: 0.7
        }
      ).and_return(mock_response)

      result = described_class.complete_with_context('Simple string')
      expect(result).to eq(mock_response)
    end

    it 'handles array of message hashes', :vcr do
      mock_client = stub_client_with_mock
      messages = [
        { role: 'user', content: 'First message' },
        { role: 'assistant', content: 'Response' },
        { role: 'user', content: 'Follow up' }
      ]

      expect(mock_client).to receive(:complete).with(
        messages,
        model: 'google/gemini-2.5-flash',
        extras: {
          max_tokens: 1000,
          temperature: 0.7
        }
      ).and_return(mock_response)

      result = described_class.complete_with_context(messages)
      expect(result).to eq(mock_response)
    end

    it 'formats array of strings as user messages', :vcr do
      mock_client = stub_client_with_mock
      messages = ['First message', 'Second message']
      expected_messages = [
        { role: 'user', content: 'First message' },
        { role: 'user', content: 'Second message' }
      ]

      expect(mock_client).to receive(:complete).with(
        expected_messages,
        model: 'google/gemini-2.5-flash',
        extras: {
          max_tokens: 1000,
          temperature: 0.7
        }
      ).and_return(mock_response)

      result = described_class.complete_with_context(messages)
      expect(result).to eq(mock_response)
    end
  end

  describe '.available_models' do
    let(:mock_models) { %w[model1 model2 model3] }

    it 'fetches and caches models', :vcr do
      mock_client = stub_client_with_mock
      expect(mock_client).to receive(:models).once.and_return(mock_models)

      # First call should fetch from API
      result1 = described_class.available_models
      expect(result1).to eq(mock_models)

      # Second call should use cache
      result2 = described_class.available_models
      expect(result2).to eq(mock_models)
    end

    it 'refreshes cache after expiry', :vcr do
      mock_client = stub_client_with_mock
      expect(mock_client).to receive(:models).twice.and_return(mock_models)

      # First call
      described_class.available_models

      # Simulate cache expiry
      allow(Time).to receive(:now).and_return(Time.now + 3700) # > 1 hour

      # Second call should refresh cache
      result = described_class.available_models
      expect(result).to eq(mock_models)
    end
  end

  describe '.clear_cache!' do
    it 'clears the model cache', :vcr do
      mock_client = stub_client_with_mock
      # Fill cache
      allow(mock_client).to receive(:models).and_return(['model1'])
      described_class.available_models

      # Clear cache
      described_class.clear_cache!

      # Should fetch from API again
      expect(mock_client).to receive(:models).and_return(['model2'])
      result = described_class.available_models
      expect(result).to eq(['model2'])
    end
  end

  describe 'convenience methods' do
    describe '.complete_cheap' do
      it 'uses the small_cheapest preset', :vcr do
        mock_client = stub_client_with_mock
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
    end

    describe '.complete_conversation' do
      it 'uses the conversation_small preset', :vcr do
        mock_client = stub_client_with_mock
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
    end

    describe '.analyze_image' do
      it 'uses the image_classification preset', :vcr do
        mock_client = stub_client_with_mock
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
  end

  describe 'private methods' do
    describe '#format_messages' do
      it 'formats different message types correctly', :vcr do
        mock_client = stub_client_with_mock
        # This tests the private method indirectly through complete_with_context
        test_cases = [
          # String input
          ['simple string', [{ role: 'user', content: 'simple string' }]],

          # Hash input
          [{ role: 'assistant', content: 'test' }, [{ role: 'assistant', content: 'test' }]],

          # Mixed array
          [['string', { role: 'user', content: 'hash' }],
           [{ role: 'user', content: 'string' }, { role: 'user', content: 'hash' }]]
        ]

        test_cases.each do |input, expected|
          expect(mock_client).to receive(:complete).with(
            expected,
            model: 'google/gemini-2.5-flash',
            extras: {
              max_tokens: 1000,
              temperature: 0.7
            }
          ).and_return(mock_response)

          described_class.complete_with_context(input)
        end
      end
    end
  end
end
