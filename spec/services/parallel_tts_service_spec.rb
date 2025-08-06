# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/parallel_tts_service'

RSpec.describe Services::ParallelTTSService, :failing do
  let(:service) { described_class.new }
  let(:mock_ha_client) { instance_double(HomeAssistantClient) }
  let(:test_message) { 'Hello from Glitch Cube!' }

  before do
    allow(service).to receive(:home_assistant).and_return(mock_ha_client)
  end

  describe '#speak_race' do
    it 'uses the first successful provider' do
      # Cloud fails, Google succeeds first
      allow(service).to receive(:speak_with_provider).with(test_message, :cloud, anything).and_raise('Cloud error')
      allow(service).to receive(:speak_with_provider).with(test_message, :google, anything).and_return(true)
      allow(service).to receive(:speak_with_provider).with(test_message, :piper, anything).and_return(true)

      expect(Services::LoggerService).to receive(:log_tts).with(
        hash_including(
          success: true,
          mode: 'race'
        )
      )

      result = service.speak_race(test_message)
      expect(result).to be true
    end

    it 'returns false if all providers fail' do
      allow(service).to receive(:speak_with_provider).and_raise('Provider error')

      expect(Services::LoggerService).to receive(:log_tts).with(
        hash_including(
          success: false,
          error: 'All providers failed',
          mode: 'race'
        )
      )

      result = service.speak_race(test_message)
      expect(result).to be false
    end

    it 'respects timeout for slow providers' do
      allow(service).to receive(:speak_with_provider) do
        sleep(6) # Exceed 5 second timeout
        true
      end

      expect(Services::LoggerService).to receive(:log_tts).with(
        hash_including(
          success: false,
          mode: 'race'
        )
      )

      result = service.speak_race(test_message, providers: [:cloud])
      expect(result).to be false
    end
  end

  describe '#speak_cascade' do
    it 'tries providers in sequence until one succeeds' do
      # First two fail, third succeeds
      allow(service).to receive(:speak_with_provider).with(test_message, :cloud, anything).and_raise('Cloud error')
      allow(service).to receive(:speak_with_provider).with(test_message, :google, anything).and_return(false)
      allow(service).to receive(:speak_with_provider).with(test_message, :piper, anything).and_return(true)

      expect(service).to receive(:sleep).with(0.5).once # Delay before second attempt
      expect(service).to receive(:sleep).with(1.0).once # Delay before third attempt

      expect(Services::LoggerService).to receive(:log_tts).with(
        hash_including(
          success: true,
          provider: 'piper',
          mode: 'cascade'
        )
      )

      result = service.speak_cascade(test_message)
      expect(result).to be true
    end

    it 'pre-warms providers in parallel' do
      expect(service).to receive(:warm_up_providers).with([:cloud, :google, :piper, :elevenlabs])
      allow(service).to receive(:speak_with_provider).and_return(true)
      allow(Services::LoggerService).to receive(:log_tts)

      service.speak_cascade(test_message)
    end
  end

  describe '#speak_redundant' do
    it 'sends to all providers in parallel' do
      expect(service).to receive(:speak_with_provider).with(test_message, :cloud, anything).and_return(true)
      expect(service).to receive(:speak_with_provider).with(test_message, :google, anything).and_return(true)

      expect(Services::LoggerService).to receive(:log_tts).with(
        hash_including(
          success: true,
          provider: 'cloud,google',
          mode: 'redundant'
        )
      )

      result = service.speak_redundant(test_message)
      expect(result).to be true
    end

    it 'succeeds if any provider succeeds' do
      allow(service).to receive(:speak_with_provider).with(test_message, :cloud, anything).and_raise('Error')
      allow(service).to receive(:speak_with_provider).with(test_message, :google, anything).and_return(true)

      expect(Services::LoggerService).to receive(:log_tts).with(
        hash_including(
          success: true,
          provider: 'google',
          mode: 'redundant'
        )
      )

      result = service.speak_redundant(test_message)
      expect(result).to be true
    end
  end

  describe '#speak_intelligent' do
    context 'with critical priority' do
      it 'uses redundant mode for reliability' do
        expect(service).to receive(:speak_redundant).with(
          test_message,
          hash_including(providers: [:cloud, :google, :piper])
        ).and_return(true)

        service.speak_intelligent(test_message, priority: :critical)
      end
    end

    context 'with fast priority' do
      it 'uses race mode for speed' do
        expect(service).to receive(:speak_race).with(
          test_message,
          hash_including(providers: [:cloud, :google])
        ).and_return(true)

        service.speak_intelligent(test_message, priority: :fast)
      end
    end

    context 'with reliable priority' do
      it 'uses cascade mode with all providers' do
        expect(service).to receive(:speak_cascade).with(
          test_message,
          hash_including(providers: [:cloud, :google, :piper, :elevenlabs])
        ).and_return(true)

        service.speak_intelligent(test_message, priority: :reliable)
      end
    end

    context 'with normal priority' do
      it 'tries cloud then falls back to google' do
        expect(service).to receive(:speak).with(test_message, provider: :cloud).and_return(false)
        expect(service).to receive(:speak).with(test_message, provider: :google).and_return(true)

        result = service.speak_intelligent(test_message, priority: :normal)
        expect(result).to be true
      end
    end
  end
end