# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/character_service'

RSpec.describe Services::CharacterService do
  let(:mock_home_assistant) { instance_double(HomeAssistantClient) }

  # Custom matcher for non-empty strings
  def a_string_that_is_not_empty
    satisfy { |s| s.is_a?(String) && !s.empty? }
  end

  before do
    # Mock HomeAssistantClient to capture the calls made to it
    allow(mock_home_assistant).to receive(:speak).and_return(true)
  end

  describe 'TTS Provider Configuration' do
    context 'for different characters' do
      it 'configures ZORP to use ElevenLabs by default', :vcr do
        zorp = described_class.new(character: :zorp)
        expect(zorp.config[:tts_provider]).to eq(:elevenlabs)
        expect(zorp.config[:voice]).to eq('Josh')
      end

      it 'configures other characters to use cloud by default', :vcr do
        %w[default buddy jax lomi].each do |character|
          service = described_class.new(character: character)
          expect(service.config[:tts_provider]).to eq(:cloud)
        end
      end
    end
  end

  describe '#speak' do
    let(:message) { 'This is a test message' }

    context 'when using cloud provider (BUDDY)' do
      let(:buddy) { described_class.new(character: :buddy, home_assistant: mock_home_assistant) }

      it 'passes correct cloud TTS specification to HomeAssistantClient', :vcr do
        expected_voice_options = {
          tts: :cloud,
          voice: 'DavisNeural',  # Plain voice without mood styling
          language: 'en-US'
        }

        expect(mock_home_assistant).to receive(:speak).with(
          a_string_that_is_not_empty,
          entity_id: 'media_player.square_voice',
          voice_options: expected_voice_options
        )

        buddy.speak(message, mood: :excited)
      end

      it 'uses plain voice without mood styling (mood feature disabled)', :vcr do
        expected_voice_options = {
          tts: :cloud,
          voice: 'DavisNeural',  # Plain voice without mood suffix
          language: 'en-US'
        }

        expect(mock_home_assistant).to receive(:speak) do |msg, options|
          expect(msg).to be_a(String)
          expect(msg).not_to be_empty
          expect(options[:entity_id]).to eq('media_player.square_voice')
          expect(options[:voice_options]).to eq(expected_voice_options)
        end

        buddy.speak(message, mood: :sad)
      end

      it 'ignores unsupported moods (mood feature disabled)', :vcr do
        # Any mood should just use the plain voice
        expected_voice_options = {
          tts: :cloud,
          voice: 'DavisNeural', # Plain voice without mood suffix
          language: 'en-US'
        }

        expect(mock_home_assistant).to receive(:speak).with(
          anything, # Message may be modified by personality
          entity_id: 'media_player.square_voice',
          voice_options: expected_voice_options
        )

        buddy.speak(message, mood: :empathetic)
      end
    end

    context 'when using ElevenLabs provider (ZORP)' do
      let(:zorp) { described_class.new(character: :zorp, home_assistant: mock_home_assistant) }

      it 'passes correct ElevenLabs TTS specification to HomeAssistantClient', :vcr do
        expected_voice_options = {
          tts: :elevenlabs,
          voice: 'Josh',
          language: 'en-US'
        }

        expect(mock_home_assistant).to receive(:speak).with(
          anything, # Message may be modified by personality
          entity_id: 'media_player.square_voice',
          voice_options: expected_voice_options
        )

        zorp.speak(message)
      end

      it 'uses plain voice for ElevenLabs', :vcr do
        # ElevenLabs uses plain voice names
        expected_voice_options = {
          tts: :elevenlabs,
          voice: 'Josh', # No mood suffix
          language: 'en-US'
        }

        # ZORP character modifies messages with speech patterns like "like,"
        expect(mock_home_assistant).to receive(:speak).with(
          anything, # Allow any message since ZORP modifies it with speech patterns
          entity_id: 'media_player.square_voice',
          voice_options: expected_voice_options
        )

        zorp.speak(message, mood: :excited)
      end
    end

    context 'with custom entity_id' do
      let(:lomi) { described_class.new(character: :lomi, home_assistant: mock_home_assistant) }

      it 'passes through custom entity_id', :vcr do
        custom_entity = 'media_player.bedroom_speaker'

        # lomi character applies speech effects that modify the message
        expect(mock_home_assistant).to receive(:speak).with(
          anything, # Allow any message since lomi modifies it with speech effects
          entity_id: custom_entity,
          voice_options: anything
        )

        lomi.speak(message, entity_id: custom_entity)
      end
    end

    context 'with TTS provider override' do
      let(:buddy) { described_class.new(character: :buddy, home_assistant: mock_home_assistant) }

      it 'allows overriding TTS provider at call time', :vcr do
        expected_voice_options = {
          tts: :elevenlabs,
          voice: 'DavisNeural', # Character's configured voice, but via ElevenLabs
          language: 'en-US'
        }

        expect(mock_home_assistant).to receive(:speak).with(
          a_string_that_is_not_empty,
          entity_id: 'media_player.square_voice',
          voice_options: expected_voice_options
        )

        buddy.speak(message, tts_provider: :elevenlabs)
      end
    end
  end

  describe 'voice selection logic' do
    let(:service) { described_class.new(character: :buddy) }

    describe '#voice_supports_variant?' do
      it 'returns true for supported voice/variant combinations', :vcr do
        expect(service.voice_supports_variant?('DavisNeural', 'excited')).to be true
        expect(service.voice_supports_variant?('AriaNeural', 'empathetic')).to be true
      end

      it 'returns false for unsupported combinations', :vcr do
        expect(service.voice_supports_variant?('DavisNeural', 'empathetic')).to be false
        expect(service.voice_supports_variant?('UnknownVoice', 'excited')).to be false
      end
    end

    describe '#best_voice_for_mood' do
      it 'returns voice with style when supported', :vcr do
        result = service.best_voice_for_mood(:excited, 'DavisNeural')
        expect(result).to eq('DavisNeural||excited')
      end

      it 'falls back to JennyNeural when preferred voice doesnt support mood', :vcr do
        result = service.best_voice_for_mood(:empathetic, 'DavisNeural')
        expect(result).to eq('AriaNeural||empathetic') # AriaNeural supports empathetic
      end

      it 'returns base voice when no voice supports the mood', :vcr do
        result = service.best_voice_for_mood(:nonexistent_mood, 'DavisNeural')
        expect(result).to eq('DavisNeural')
      end
    end
  end

  describe 'Voice verification for each persona' do
    let(:mock_ha) { instance_double(HomeAssistantClient) }

    before do
      allow(HomeAssistantClient).to receive(:new).and_return(mock_ha)
      allow(mock_ha).to receive(:speak).and_return(true)
    end

    it 'uses correct voice for each character', :vcr do
      # Test each character maps to correct voice
      character_voices = {
        default: 'JennyNeural',
        buddy: 'DavisNeural',
        jax: 'GuyNeural',
        lomi: 'AriaNeural'
      }

      character_voices.each do |character, expected_voice|
        service = described_class.new(character: character)

        expect(mock_ha).to receive(:speak).with(
          anything,
          entity_id: 'media_player.square_voice',
          voice_options: hash_including(
            tts: :cloud,
            voice: expected_voice,
            language: 'en-US'
          )
        )

        service.speak("Test for #{character}")
      end
    end

    it 'never sends voice_id, always sends voice', :vcr do
      service = described_class.new(character: :buddy)

      expect(mock_ha).to receive(:speak) do |_msg, entity_id:, voice_options:|
        # Verify we send 'voice' not 'voice_id'
        expect(voice_options).to have_key(:voice)
        expect(voice_options).not_to have_key(:voice_id)
        expect(voice_options[:voice]).to eq('DavisNeural')
        true
      end

      service.speak('Test')
    end
  end
end
