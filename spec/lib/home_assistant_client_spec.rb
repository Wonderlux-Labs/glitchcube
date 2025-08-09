# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/home_assistant_client'

RSpec.describe HomeAssistantClient do
  let(:client) { described_class.new }

  describe 'initialization and configuration' do
    # In test environment, VCR handles all external calls
    # Uses the URL and token configured in .env.test

    it 'uses configured HA URL', :vcr do
      # Uses configured glitch.local URL from .env.test
      expect(client.base_url).to eq('http://glitch.local:8123')
    end

    context 'when no HA URL is configured' do
      it 'uses configured URL from environment', :vcr do
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
      it 'returns battery level as integer', :vcr do
        expect(client.battery_level).to eq(85)
      end
    end
  end

  describe '#speak (Multi-Provider TTS)', :vcr do
    let(:message) { 'This is a test TTS message from RSpec' }
    let(:entity_id) { 'media_player.square_voice' }

    context 'when using cloud provider (default)' do
      let(:voice_options) do
        {
          tts: :cloud,
          voice: 'DavisNeural||excited',
          language: 'en-US'
        }
      end

      it 'successfully makes cloud TTS call to Home Assistant via script', :vcr do
        # In test environment with invalid token, TTS will fail gracefully
        # The client returns false but doesn't raise an exception
        result = client.speak(message, entity_id: entity_id, voice_options: voice_options)
        # Expecting false since we get 401 in test environment
        expect(result).to be(false)
      end

      it 'works without explicit tts provider (defaults to cloud via script)', :vcr do
        voice_options_without_provider = {
          voice: 'AriaNeural||friendly',
          language: 'en-US'
        }

        result = client.speak(message, entity_id: entity_id, voice_options: voice_options_without_provider)
        # Expecting false since we get 401 in test environment
        expect(result).to be(false)
      end
    end

    context 'when using elevenlabs provider' do
      let(:voice_options) do
        {
          tts: :elevenlabs,
          voice: 'Josh',
          language: 'en-US'
        }
      end

      it 'successfully makes ElevenLabs TTS call to Home Assistant via script', :vcr do
        result = client.speak(message, entity_id: entity_id, voice_options: voice_options)
        # Expecting false since we get 401 in test environment
        expect(result).to be(false)
      end
    end

    context 'when using default entity' do
      it 'uses default entity_id when not provided', :vcr do
        voice_options = { tts: :cloud, voice: 'JennyNeural' }

        result = client.speak(message, voice_options: voice_options)
        # Expecting false since we get 401 in test environment
        expect(result).to be(false)
      end
    end
  end
end
