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
    # Clear the memoized client
    described_class.instance_variable_set(:@client, nil)
  end

  describe '.complete' do
    it 'makes a simple completion request' do
      mock_client = instance_double(OpenRouter::Client)
      allow(OpenRouter::Client).to receive(:new).and_return(mock_client)
      
      expect(mock_client).to receive(:complete).with({
        model: 'google/gemini-2.0-flash-thinking-exp:free',
        messages: [{ role: 'user', content: 'Test prompt' }],
        max_tokens: 500,
        temperature: 0.7
      }).and_return(mock_response)

      result = described_class.complete('Test prompt')
      expect(result).to eq(mock_response)
    end

    it 'accepts custom options' do
      expect(mock_client).to receive(:complete).with({
        model: 'different-model',
        messages: [{ role: 'user', content: 'Test prompt' }],
        max_tokens: 100,
        temperature: 0.3
      }).and_return(mock_response)

      result = described_class.complete('Test prompt', 
                                       model: 'different-model',
                                       max_tokens: 100,
                                       temperature: 0.3)
      expect(result).to eq(mock_response)
    end

    it 'raises error for blacklisted models' do
      expect {
        described_class.complete('Test prompt', model: 'openai/o1-pro')
      }.to raise_error(ArgumentError, /blacklisted due to high cost/)
    end
  end

  describe '.complete_with_context' do
    it 'handles string messages' do
      expect(mock_client).to receive(:complete).with({
        model: 'google/gemini-2.0-flash-thinking-exp:free',
        messages: [{ role: 'user', content: 'Simple string' }],
        max_tokens: 500,
        temperature: 0.7
      }).and_return(mock_response)

      result = described_class.complete_with_context('Simple string')
      expect(result).to eq(mock_response)
    end

    it 'handles array of message hashes' do
      messages = [
        { role: 'user', content: 'First message' },
        { role: 'assistant', content: 'Response' },
        { role: 'user', content: 'Follow up' }
      ]

      expect(mock_client).to receive(:complete).with({
        model: 'google/gemini-2.0-flash-thinking-exp:free',
        messages: messages,
        max_tokens: 500,
        temperature: 0.7
      }).and_return(mock_response)

      result = described_class.complete_with_context(messages)
      expect(result).to eq(mock_response)
    end

    it 'formats array of strings as user messages' do
      messages = ['First message', 'Second message']
      expected_messages = [
        { role: 'user', content: 'First message' },
        { role: 'user', content: 'Second message' }
      ]

      expect(mock_client).to receive(:complete).with({
        model: 'google/gemini-2.0-flash-thinking-exp:free',
        messages: expected_messages,
        max_tokens: 500,
        temperature: 0.7
      }).and_return(mock_response)

      result = described_class.complete_with_context(messages)
      expect(result).to eq(mock_response)
    end
  end

  describe '.available_models' do
    let(:mock_models) { ['model1', 'model2', 'model3'] }

    it 'fetches and caches models' do
      expect(mock_client).to receive(:models).once.and_return(mock_models)
      
      # First call should fetch from API
      result1 = described_class.available_models
      expect(result1).to eq(mock_models)
      
      # Second call should use cache
      result2 = described_class.available_models
      expect(result2).to eq(mock_models)
    end

    it 'refreshes cache after expiry' do
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
    it 'clears the model cache' do
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
      it 'uses the small_cheapest preset' do
        expect(mock_client).to receive(:complete).with(
          hash_including(model: 'meta-llama/llama-3.2-3b-instruct')
        ).and_return(mock_response)

        described_class.complete_cheap('Test prompt')
      end
    end

    describe '.complete_conversation' do
      it 'uses the conversation_small preset' do
        expect(mock_client).to receive(:complete).with(
          hash_including(model: 'qwen/qwen3-235b-a22b-thinking-2507')
        ).and_return(mock_response)

        described_class.complete_conversation('Test prompt')
      end
    end

    describe '.analyze_image' do
      it 'uses the image_classification preset' do
        expect(mock_client).to receive(:complete).with(
          hash_including(model: 'qwen/qwen2.5-vl-72b-instruct:free')
        ).and_return(mock_response)

        described_class.analyze_image('Analyze this image')
      end
    end
  end

  describe 'private methods' do
    describe '#format_messages' do
      it 'formats different message types correctly' do
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
            hash_including(messages: expected)
          ).and_return(mock_response)
          
          described_class.complete_with_context(input)
        end
      end
    end
  end
end