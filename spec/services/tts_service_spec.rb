# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/tts_service'

RSpec.describe Services::TTSService do
  let(:home_assistant) { double('HomeAssistantClient') }
  let(:service) { described_class.new(home_assistant: home_assistant) }

  describe '#speak' do
    context 'with basic message' do
      it 'sends TTS request to Home Assistant' do
        expect(home_assistant).to receive(:post).with(
          '/api/services/tts/speak',
          hash_including(
            target: { entity_id: 'tts.home_assistant_cloud' },
            data: hash_including(
              media_player_entity_id: 'media_player.square_voice',
              message: 'Hello world',
              language: 'en-US',
              cache: true
            )
          )
        ).and_return(true)

        expect(Services::LoggerService).to receive(:log_tts).with(
          hash_including(
            message: 'Hello world',
            success: true,
            provider: 'cloud'
          )
        )

        result = service.speak('Hello world')
        expect(result).to be true
      end
    end

    context 'with voice selection' do
      it 'includes voice in options' do
        expect(home_assistant).to receive(:post).with(
          '/api/services/tts/speak',
          hash_including(
            data: hash_including(
              options: { voice: 'AriaNeural' }
            )
          )
        ).and_return(true)

        expect(Services::LoggerService).to receive(:log_tts)

        service.speak('Test message', voice: :aria)
      end

      it 'accepts custom voice string' do
        expect(home_assistant).to receive(:post).with(
          '/api/services/tts/speak',
          hash_including(
            data: hash_including(
              options: { voice: 'CustomVoiceNeural' }
            )
          )
        ).and_return(true)

        expect(Services::LoggerService).to receive(:log_tts)

        service.speak('Test message', voice: 'CustomVoiceNeural')
      end
    end

    context 'with mood' do
      it 'applies style and speed for friendly mood' do
        expect(home_assistant).to receive(:post).with(
          '/api/services/tts/speak',
          hash_including(
            data: hash_including(
              options: { 
                voice: 'JennyNeural',
                style: 'friendly'
              }
            )
          )
        ).and_return(true)

        expect(Services::LoggerService).to receive(:log_tts).with(
          hash_including(mood: 'friendly')
        )

        service.speak('Hello friend', mood: :friendly)
      end

      it 'adjusts speed for sad mood' do
        expect(home_assistant).to receive(:post).with(
          '/api/services/tts/speak',
          hash_including(
            data: hash_including(
              options: hash_including(
                voice: 'JennyNeural',
                style: 'sad',
                speed: 90
              )
            )
          )
        ).and_return(true)

        expect(Services::LoggerService).to receive(:log_tts)

        service.speak('Sad message', mood: :sad)
      end
    end

    context 'with different providers' do
      it 'uses Google TTS provider' do
        expect(home_assistant).to receive(:call_service).with(
          'tts',
          'google_translate',
          hash_including(
            entity_id: 'media_player.square_voice',
            message: 'Test message'
          )
        ).and_return(true)

        expect(Services::LoggerService).to receive(:log_tts)

        service.speak('Test message', provider: :google)
      end

      it 'uses chime_tts for announcements with chime' do
        expect(home_assistant).to receive(:call_service).with(
          'chime_tts',
          'say',
          hash_including(
            entity_id: 'media_player.square_voice',
            message: 'Doorbell',
            chime_path: 'doorbell',
            announce: true
          )
        ).and_return(true)

        expect(Services::LoggerService).to receive(:log_tts)

        service.speak('Doorbell', chime: 'doorbell', announce: true)
      end
    end

    context 'with volume control' do
      it 'sets volume after TTS' do
        expect(home_assistant).to receive(:post).and_return(true)
        expect(home_assistant).to receive(:call_service).with(
          'media_player',
          'volume_set',
          entity_id: 'media_player.square_voice',
          volume_level: 0.7
        )

        expect(Services::LoggerService).to receive(:log_tts)

        service.speak('Test', volume: 0.7)
      end
    end

    context 'with empty message' do
      it 'returns false without calling HA' do
        expect(home_assistant).not_to receive(:post)
        expect(home_assistant).not_to receive(:call_service)

        result = service.speak('')
        expect(result).to be false
      end

      it 'returns false for nil message' do
        expect(home_assistant).not_to receive(:post)
        
        result = service.speak(nil)
        expect(result).to be false
      end
    end

    context 'error handling' do
      it 'falls back to Google TTS on error' do
        expect(home_assistant).to receive(:post).and_raise(
          HomeAssistantClient::Error, 'Cloud TTS failed'
        )
        
        expect(home_assistant).to receive(:call_service).with(
          'tts',
          'google_translate_say',
          entity_id: 'media_player.square_voice',
          message: 'Test message'
        ).and_return(true)

        expect(Services::LoggerService).to receive(:log_tts).with(
          hash_including(
            success: false,
            error: 'Cloud TTS failed'
          )
        )

        result = service.speak('Test message')
        expect(result).to be true
      end

      it 'returns false when all TTS methods fail' do
        expect(home_assistant).to receive(:post).and_raise(
          HomeAssistantClient::Error, 'Cloud TTS failed'
        )
        
        expect(home_assistant).to receive(:call_service).and_raise(
          HomeAssistantClient::Error, 'Google TTS also failed'
        )

        expect(Services::LoggerService).to receive(:log_tts)

        result = service.speak('Test message')
        expect(result).to be false
      end
    end
  end

  describe 'convenience methods' do
    describe '#speak_friendly' do
      it 'speaks with friendly mood' do
        expect(service).to receive(:speak).with(
          'Hello!',
          mood: :friendly,
          volume: 0.8
        )

        service.speak_friendly('Hello!', volume: 0.8)
      end
    end

    describe '#whisper' do
      it 'speaks with whisper mood' do
        expect(service).to receive(:speak).with(
          'Shh...',
          mood: :whisper
        )

        service.whisper('Shh...')
      end
    end

    describe '#announce' do
      it 'speaks with announce flag' do
        expect(service).to receive(:speak).with(
          'Attention',
          announce: true
        )

        service.announce('Attention')
      end
    end
  end

  describe '#broadcast' do
    it 'sends message to multiple entities' do
      entities = ['media_player.kitchen', 'media_player.bedroom']
      
      entities.each do |entity|
        expect(service).to receive(:speak).with(
          'Broadcast message',
          entity_id: entity
        ).and_return(true)
      end

      result = service.broadcast('Broadcast message', entities: entities)
      expect(result).to be true
    end

    it 'returns false if any entity fails' do
      entities = ['media_player.kitchen', 'media_player.bedroom']
      
      expect(service).to receive(:speak).with(
        'Test',
        entity_id: 'media_player.kitchen'
      ).and_return(true)
      
      expect(service).to receive(:speak).with(
        'Test',
        entity_id: 'media_player.bedroom'
      ).and_return(false)

      result = service.broadcast('Test', entities: entities)
      expect(result).to be false
    end
  end
end