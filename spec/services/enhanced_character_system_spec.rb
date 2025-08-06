# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Enhanced Character System' do
  describe 'character-specific tools' do
    it 'buddy gets customer service tools' do
      service = Services::SystemPromptService.new(
        character: 'buddy',
        context: { available_tools: %w[customer_satisfaction_survey technical_support booking_system] }
      )
      prompt = service.generate

      expect(prompt).to include('AVAILABLE TOOLS')
      expect(prompt).to include('Customer Satisfaction Survey')
      expect(prompt).to include('Technical Support')
    end

    it 'lomi gets performance and aesthetic tools' do
      service = Services::SystemPromptService.new(
        character: 'lomi',
        context: { available_tools: %w[runway_lighting music_control shade_generator] }
      )
      prompt = service.generate

      expect(prompt).to include('AVAILABLE TOOLS')
      expect(prompt).to include('Runway Lighting')
      expect(prompt).to include('Shade Generator')
    end

    it 'jax gets bartending and music tools' do
      service = Services::SystemPromptService.new(
        character: 'jax',
        context: { available_tools: %w[classic_music_player life_advice_dispenser electronic_music_killer] }
      )
      prompt = service.generate

      expect(prompt).to include('AVAILABLE TOOLS')
      expect(prompt).to include('Classic Music Player')
      expect(prompt).to include('Electronic Music Killer')
    end
  end

  describe 'context integration' do
    let(:rich_context) do
      {
        current_location: 'Center Camp',
        temperature: '95°F',
        dust_level: 'moderate',
        nearby_sounds: 'electronic music (EDM)',
        people_detected: 3,
        current_mood: 'energetic',
        battery_level: '75%',
        time_of_day: 'afternoon'
      }
    end

    it 'includes environmental context in prompts' do
      service = Services::SystemPromptService.new(character: 'buddy', context: rich_context)
      prompt = service.generate

      expect(prompt).to include('CURRENT ENVIRONMENT')
      expect(prompt).to include('Center Camp')
      expect(prompt).to include('95°F')
      expect(prompt).to include('3')
    end

    it 'tailors context to character personality' do
      # JAX should hate the electronic music context
      service = Services::SystemPromptService.new(character: 'jax', context: rich_context)
      prompt = service.generate

      expect(prompt).to include('electronic music (EDM)')
      expect(prompt).to include('Current Mood: energetic')
    end
  end

  describe 'character-specific context filtering' do
    let(:context) { { battery_level: '25%', dust_storm_warning: true, party_mode: 'active' } }

    it 'buddy focuses on helpful service context' do
      service = Services::SystemPromptService.new(character: 'buddy', context: context)
      prompt = service.generate

      expect(prompt).to include('Battery Level: 25%')
      expect(prompt).to include('Party Mode: active')
    end

    it 'zorp focuses on party-related context' do
      service = Services::SystemPromptService.new(character: 'zorp', context: context)
      prompt = service.generate

      expect(prompt).to include('Party Mode: active')
    end
  end
end
