# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Enhanced Character System' do
  describe 'character-specific tools' do
    it 'buddy gets speech and display tools' do
      # Use our actual tool system instead of fake tools
      tools = Services::ToolRegistryService.get_tools_for_character('buddy')
      service = Services::SystemPromptService.new(
        character: 'buddy',
        context: { tools: tools }
      )
      prompt = service.generate

      # Buddy should get SpeechTool and DisplayTool based on our persona mapping
      expect(prompt).to include('speak_text')
      expect(prompt).to include('display_text')
    end

    it 'lomi gets speech and display tools' do
      tools = Services::ToolRegistryService.get_tools_for_character('lomi')
      service = Services::SystemPromptService.new(
        character: 'lomi',
        context: { tools: tools }
      )
      prompt = service.generate

      # Lomi should get SpeechTool and DisplayTool based on our persona mapping
      expect(prompt).to include('speak_text')
      expect(prompt).to include('display_text')
    end

    it 'jax gets speech and lighting tools' do
      tools = Services::ToolRegistryService.get_tools_for_character('jax')
      service = Services::SystemPromptService.new(
        character: 'jax',
        context: { tools: tools }
      )
      prompt = service.generate

      # Jax should get SpeechTool and LightingTool based on our persona mapping
      expect(prompt).to include('speak_text')
      expect(prompt).to include('set_state')
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
