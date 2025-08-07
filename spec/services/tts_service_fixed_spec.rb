# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/tts_service'

RSpec.describe Services::TTSService do
  let(:mock_ha_client) { instance_double(HomeAssistantClient) }
  let(:tts_service) { described_class.new(home_assistant: mock_ha_client) }

  describe '#speak' do
    context 'with cloud provider' do
      it 'calls Home Assistant service correctly' do
        # The data structure that should be sent to the glitchcube_tts script
        expected_data = {
          message: 'Test message',
          media_player: 'media_player.square_voice',
          language: 'en-US',
          cache: true,
          voice: 'JennyNeural'
        }

        # Mock the call_service method for the script call
        expect(mock_ha_client).to receive(:call_service)
          .with('script', 'glitchcube_tts', expected_data)
          .and_return(true)

        result = tts_service.speak('Test message')
        expect(result).to be true
      end

      it 'handles mood parameter correctly' do
        expected_data = {
          message: 'Excited message!',
          media_player: 'media_player.square_voice',
          language: 'en-US',
          cache: true,
          voice: 'JennyNeural||excited'
        }

        expect(mock_ha_client).to receive(:call_service)
          .with('script', 'glitchcube_tts', expected_data)
          .and_return(true)

        result = tts_service.speak('Excited message!', mood: :excited)
        expect(result).to be true
      end
    end

    context 'when TTS fails' do
      it 'does not attempt Google TTS fallback' do
        # First call fails - update to match actual script call
        expect(mock_ha_client).to receive(:call_service)
          .with('script', 'glitchcube_tts', anything)
          .and_raise(StandardError, 'TTS failed')

        # Should NOT attempt to call google_translate_say
        expect(mock_ha_client).not_to receive(:call_service)
          .with('tts', 'google_translate_say', anything)

        # Since TTS will fail and return false, no "completely failed" output expected
        expect(tts_service.speak('Test message')).to be false
      end
    end
  end
end
