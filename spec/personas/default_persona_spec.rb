# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/personas/base_persona'
require_relative '../../lib/personas/buddy_persona'
require_relative '../../lib/personas/default_persona'

RSpec.describe Personas::DefaultPersona do
  let(:context) { {} }
  let(:persona) { described_class.new(context) }

  describe 'inheritance' do
    it 'inherits from BuddyPersona' do
      expect(described_class.superclass).to eq(Personas::BuddyPersona)
    end

    it 'uses buddy prompt file by default' do
      expect(persona.prompt_file).to eq('buddy.txt')
    end

    it 'inherits buddy fallback responses' do
      responses = persona.fallback_responses
      expect(responses).to include("You're fucking amazing and I believe in you!")
      expect(responses).to include("Holy shit, that's an interesting thought! Let me help you with that!")
    end

    it 'inherits buddy tool set' do
      # Should have same tools as BuddyPersona
      tools = persona.available_tools
      expect(tools).to be_an(Array)
      expect(tools).not_to be_empty
    end
  end

  describe 'registration' do
    it 'is registered as default persona' do
      # Should be able to create via factory as 'default'
      default_persona = Personas::BasePersona.create('default')
      # Default should actually create a BuddyPersona (per BasePersona logic)
      expect(default_persona).to be_a(Personas::BuddyPersona)
    end

    it 'can be explicitly registered if needed' do
      # Save the original registry state
      original_registry = Personas::BasePersona.instance_variable_get(:@registry).dup

      begin
        # Register DefaultPersona explicitly
        Personas::BasePersona.register_persona('explicit_default', Personas::DefaultPersona)

        # Now it should create DefaultPersona specifically
        explicit_default = Personas::BasePersona.create('explicit_default')
        expect(explicit_default).to be_a(Personas::DefaultPersona)
      ensure
        # Restore the original registry state to prevent test pollution
        Personas::BasePersona.instance_variable_set(:@registry, original_registry)
      end
    end
  end

  describe 'customization potential' do
    it 'can override methods from BuddyPersona' do
      # Test that we CAN override if needed
      allow(persona).to receive(:prompt_file).and_return('custom.txt')
      expect(persona.prompt_file).to eq('custom.txt')
    end

    it 'maintains separate identity from buddy' do
      expect(persona.name).to eq('default')
    end
  end

  describe 'system prompt generation' do
    it 'generates a complete system prompt' do
      prompt = persona.generate_system_prompt
      expect(prompt).to include('CURRENT DATE AND TIME')
      expect(prompt).to include('BUDDY')
    end
  end

  describe 'fallback behavior' do
    it 'provides fallback response when needed' do
      response = persona.generate_fallback_response('test message')
      expect(response).to be_a(String)
      expect(response).not_to be_empty
    end

    it 'provides offline response when needed' do
      response = persona.generate_offline_response('test message')
      # Check that it contains any of the buddy offline keywords
      expect(response.downcase).to match(/circuits|shit|brain|technical|offline/)
      expect(response).to be_a(String)
    end
  end
end
