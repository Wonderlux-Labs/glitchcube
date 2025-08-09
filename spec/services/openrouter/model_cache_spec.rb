# frozen_string_literal: true

require 'spec_helper'
require 'services/openrouter/model_cache'

RSpec.describe Services::OpenRouter::ModelCache do
  let(:cache) { described_class.new }
  let(:client) { double('OpenRouter::Client') }
  let(:models_response) do
    [
      { 'id' => 'model-1', 'name' => 'Test Model 1' },
      { 'id' => 'model-2', 'name' => 'Test Model 2' }
    ]
  end

  describe '#available_models' do
    context 'when cache is empty' do
      it 'fetches models from the client', :vcr do
        expect(client).to receive(:models).and_return(models_response)

        result = cache.available_models(client)
        expect(result).to eq(models_response)
      end

      it 'caches the fetched models', :vcr do
        expect(client).to receive(:models).once.and_return(models_response)

        # First call fetches from API
        cache.available_models(client)

        # Second call should use cache (no API call)
        result = cache.available_models(client)
        expect(result).to eq(models_response)
      end
    end

    context 'when cache has expired' do
      it 'fetches fresh models from the client', :vcr do
        # First call to populate cache
        expect(client).to receive(:models).and_return(models_response)
        cache.available_models(client)

        # Simulate cache expiration
        allow(Time).to receive(:now).and_return(Time.now + 3601)

        # Should fetch again
        expect(client).to receive(:models).and_return(models_response)
        result = cache.available_models(client)

        expect(result).to eq(models_response)
      end
    end

    context 'when cache is valid' do
      it 'returns cached models without API call', :vcr do
        # Populate cache
        expect(client).to receive(:models).once.and_return(models_response)
        cache.available_models(client)

        # Use cache
        result = cache.available_models(client)
        expect(result).to eq(models_response)
      end
    end
  end

  describe '#clear!' do
    it 'clears all cached data', :vcr do
      # Populate cache
      expect(client).to receive(:models).and_return(models_response)
      cache.available_models(client)

      # Clear cache
      cache.clear!

      # Next call should fetch from API again
      expect(client).to receive(:models).and_return(models_response)
      cache.available_models(client)
    end
  end
end
