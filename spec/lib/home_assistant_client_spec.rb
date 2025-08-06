# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/home_assistant_client'

RSpec.describe HomeAssistantClient do
  let(:client) { described_class.new }

  describe 'with mock enabled' do
    before do
      allow(GlitchCube.config.home_assistant).to receive(:mock_enabled).and_return(true)
    end

    it 'uses HA URL from config' do
      client = described_class.new
      expect(client.base_url).to eq('http://localhost:4567/mock_ha')
    end

    it 'uses token from config' do
      client = described_class.new
      expect(client.token).to eq('test-ha-token')
    end
  end

  describe 'with mock disabled' do
    before do
      allow(GlitchCube.config.home_assistant).to receive_messages(mock_enabled: false, url: 'http://real-ha:8123', token: 'real-token')
    end

    it 'uses real HA URL' do
      client = described_class.new
      expect(client.base_url).to eq('http://real-ha:8123')
    end

    it 'uses real token' do
      client = described_class.new
      expect(client.token).to eq('real-token')
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
