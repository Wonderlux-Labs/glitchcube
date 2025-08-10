# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Personas::PersonaFactory do
  describe '.create' do
    it 'creates a BuddyPersona for buddy' do
      persona = described_class.create('buddy')
      expect(persona).to be_a(Personas::BuddyPersona)
    end

    it 'creates a JaxPersona for jax' do
      persona = described_class.create('jax')
      expect(persona).to be_a(Personas::JaxPersona)
    end

    it 'creates a LomiPersona for lomi' do
      persona = described_class.create('lomi')
      expect(persona).to be_a(Personas::LomiPersona)
    end

    it 'creates a ZorpPersona for zorp' do
      persona = described_class.create('zorp')
      expect(persona).to be_a(Personas::ZorpPersona)
    end

    it 'defaults to BuddyPersona for unknown personas' do
      persona = described_class.create('unknown')
      expect(persona).to be_a(Personas::BuddyPersona)
    end

    it 'defaults to BuddyPersona for nil' do
      persona = described_class.create(nil)
      expect(persona).to be_a(Personas::BuddyPersona)
    end

    it 'handles default as buddy' do
      persona = described_class.create('default')
      expect(persona).to be_a(Personas::BuddyPersona)
    end

    it 'passes context to persona' do
      context = { temperature: 0.5 }
      persona = described_class.create('buddy', context)
      expect(persona.context).to eq(context)
    end
  end

  describe '.available_personas' do
    it 'returns list of available personas' do
      expect(described_class.available_personas).to contain_exactly('buddy', 'jax', 'lomi', 'zorp')
    end
  end

  describe '.persona_exists?' do
    it 'returns true for known personas' do
      %w[buddy jax lomi zorp].each do |name|
        expect(described_class.persona_exists?(name)).to be true
      end
    end

    it 'returns false for unknown personas' do
      expect(described_class.persona_exists?('unknown')).to be false
    end

    it 'handles default as buddy' do
      expect(described_class.persona_exists?('default')).to be false
    end
  end
end
