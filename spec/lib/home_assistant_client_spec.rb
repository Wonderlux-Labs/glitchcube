# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/home_assistant_client'

RSpec.describe HomeAssistantClient do
  let(:client) { described_class.new }

  describe 'initialization and configuration' do
    # In test environment, VCR handles all external calls
    # Uses the URL and token configured in .env.test

    it 'uses configured HA URL' do
      # Uses configured glitch.local URL from .env.test
      expect(client.base_url).to eq('http://glitch.local:8123')
    end

    it 'uses token from config' do
      # In test environment, uses a consistent test token for VCR
      expect(client.token).to be_a(String)
      expect(client.token).to eq('test-ha-token') # Consistent test token
    end

    context 'when no HA URL is configured' do
      it 'uses configured URL from environment' do
        # Test that client uses configured URL
        client = described_class.new(base_url: nil)

        # Uses the URL configured in .env.test
        expect(client.base_url).to eq('http://glitch.local:8123')
      end
    end
  end

  describe 'convenience methods' do
    let(:mock_state) { { 'state' => '85' } }

    before do
      allow(client).to receive(:state).with('sensor.battery_level').and_return(mock_state)
    end

    describe '#battery_level' do
      it 'returns battery level as integer' do
        expect(client.battery_level).to eq(85)
      end
    end
  end
end
