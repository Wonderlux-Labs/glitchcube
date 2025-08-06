# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/tts_service'

RSpec.describe Services::TTSService do
  let(:mock_ha_client) { instance_double(HomeAssistantClient) }
  let(:tts_service) { described_class.new(home_assistant: mock_ha_client) }

  describe '#speak' do
    context 'with cloud provider' do
      it 'calls Home Assistant service correctly' do
        # The data structure that should be sent to HA
        expected_data = {
          target: {
            entity_id: 'tts.home_assistant_cloud'
          },
          data: {
            media_player_entity_id: 'media_player.square_voice',
            message: 'Test message',
            language: 'en-US',
            options: {
              voice: 'JennyNeural'
            }
          }
        }

        # Mock the call_service method (NOT post!)
        expect(mock_ha_client).to receive(:call_service)
          .with('tts', 'speak', expected_data)
          .and_return(true)

        result = tts_service.speak('Test message')
        expect(result).to be true
      end

      it 'handles mood parameter correctly' do
        expected_data = {
          target: {
            entity_id: 'tts.home_assistant_cloud'
          },
          data: {
            media_player_entity_id: 'media_player.square_voice',
            message: 'Excited message!',
            language: 'en-US',
            options: {
              voice: 'JennyNeural',
              style: 'excited'
            }
          }
        }

        expect(mock_ha_client).to receive(:call_service)
          .with('tts', 'speak', expected_data)
          .and_return(true)

        result = tts_service.speak('Excited message!', mood: :excited)
        expect(result).to be true
      end
    end

    context 'when TTS fails' do
      it 'does not attempt Google TTS fallback' do
        # First call fails
        expect(mock_ha_client).to receive(:call_service)
          .with('tts', 'speak', anything)
          .and_raise(StandardError, 'TTS failed')

        # Should NOT attempt to call google_translate_say
        expect(mock_ha_client).not_to receive(:call_service)
          .with('tts', 'google_translate_say', anything)

        # Capture output to verify error message
        expect do
          tts_service.speak('Test message')
        end.to output(/TTS completely failed/).to_stdout

        # Method should return false on failure
        expect(tts_service.speak('Test message')).to be false
      end
    end
  end
end
