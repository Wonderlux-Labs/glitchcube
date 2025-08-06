# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/modules/conversation_module'

RSpec.describe ConversationModule do
  let(:conversation_module) { described_class.new }

  describe '#speak_response' do
    let(:mock_tts_service) { instance_double(Services::TTSService) }

    before do
      allow(Services::TTSService).to receive(:new).and_return(mock_tts_service)
    end

    it 'uses TTSService instead of HomeAssistantClient' do
      # Should create a TTS service
      expect(Services::TTSService).to receive(:new).and_return(mock_tts_service)

      # Should call speak on the TTS service with correct parameters
      expect(mock_tts_service).to receive(:speak)
        .with('Hello world', mood: 'playful', cache: true)
        .and_return(true)

      # Should log the TTS call
      expect(Services::LoggerService).to receive(:log_tts)
        .with(hash_including(message: 'Hello world', success: true))

      conversation_module.speak_response('Hello world', mood: 'playful')
    end

    it 'handles different moods/personas' do
      expect(mock_tts_service).to receive(:speak)
        .with('Excited message', mood: 'excited', cache: true)
        .and_return(true)

      expect(Services::LoggerService).to receive(:log_tts)
        .with(hash_including(message: 'Excited message', success: true))

      conversation_module.speak_response('Excited message', persona: 'excited')
    end

    it 'handles TTS failures gracefully' do
      expect(mock_tts_service).to receive(:speak)
        .and_raise(StandardError, 'TTS error')

      expect(Services::LoggerService).to receive(:log_tts)
        .with(hash_including(success: false, error: /TTS error/))

      # Should not raise error, just log it
      expect do
        conversation_module.speak_response('Test message', {})
      end.not_to raise_error
    end

    it 'skips empty messages' do
      expect(mock_tts_service).not_to receive(:speak)

      conversation_module.speak_response('', {})
      conversation_module.speak_response(nil, {})
      conversation_module.speak_response('   ', {})
    end
  end
end
