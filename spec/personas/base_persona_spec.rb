# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/personas/base_persona'
require_relative '../../lib/personas/buddy_persona'
require_relative '../../lib/personas/jax_persona'

RSpec.describe Personas::BasePersona do
  describe 'registry pattern' do
    before do
      # Clear registry for clean tests
      described_class.instance_variable_set(:@registry, {})
    end

    after do
      # Re-register personas after tests
      Personas::PersonaFactory.register_all if defined?(Personas::PersonaFactory)
    end

    describe '.register_persona' do
      it 'registers a persona class with a name' do
        described_class.register_persona('test', Personas::BuddyPersona)
        expect(described_class.available_personas).to include('test')
      end

      it 'normalizes persona names to lowercase' do
        described_class.register_persona('TEST', Personas::BuddyPersona)
        expect(described_class.available_personas).to include('test')
        expect(described_class.available_personas).not_to include('TEST')
      end

      it 'allows overwriting existing registrations' do
        described_class.register_persona('test', Personas::BuddyPersona)
        described_class.register_persona('test', Personas::JaxPersona)

        persona = described_class.create('test')
        expect(persona).to be_a(Personas::JaxPersona)
      end
    end

    describe '.create' do
      before do
        described_class.register_persona('buddy', Personas::BuddyPersona)
        described_class.register_persona('jax', Personas::JaxPersona)
      end

      it 'creates the correct persona class' do
        buddy = described_class.create('buddy')
        expect(buddy).to be_a(Personas::BuddyPersona)

        jax = described_class.create('jax')
        expect(jax).to be_a(Personas::JaxPersona)
      end

      it 'passes context to persona constructor' do
        context = { test: 'value' }
        persona = described_class.create('buddy', context)
        expect(persona.context).to eq(context)
      end

      it 'defaults to BuddyPersona for unknown personas' do
        persona = described_class.create('unknown')
        expect(persona).to be_a(Personas::BuddyPersona)
      end

      it 'defaults to BuddyPersona for default persona' do
        persona = described_class.create('default')
        expect(persona).to be_a(Personas::BuddyPersona)
      end

      it 'handles nil persona name' do
        persona = described_class.create(nil)
        expect(persona).to be_a(Personas::BuddyPersona)
      end

      it 'handles empty string persona name' do
        persona = described_class.create('')
        expect(persona).to be_a(Personas::BuddyPersona)
      end
    end

    describe '.available_personas' do
      it 'returns list of registered persona names' do
        described_class.register_persona('persona1', Personas::BuddyPersona)
        described_class.register_persona('persona2', Personas::JaxPersona)

        expect(described_class.available_personas).to contain_exactly('persona1', 'persona2')
      end

      it 'returns empty array when no personas registered' do
        expect(described_class.available_personas).to be_empty
      end
    end

    describe '.persona_exists?' do
      before do
        described_class.register_persona('buddy', Personas::BuddyPersona)
      end

      it 'returns true for registered personas' do
        expect(described_class.persona_exists?('buddy')).to be true
      end

      it 'returns false for unregistered personas' do
        expect(described_class.persona_exists?('unknown')).to be false
      end

      it 'is case insensitive' do
        expect(described_class.persona_exists?('BUDDY')).to be true
        expect(described_class.persona_exists?('Buddy')).to be true
      end
    end
  end

  describe 'abstract methods' do
    let(:context) { {} }

    # Create a test subclass that implements required methods
    let(:test_persona_class) do
      Class.new(described_class) do
        def self.name
          'TestPersona'
        end

        def prompt_file
          'test.txt'
        end

        def available_tools
          []
        end

        def fallback_responses
          ['Test fallback']
        end

        def offline_responses
          ['Test offline']
        end
      end
    end

    let(:persona) { test_persona_class.new(context) }

    it 'requires subclasses to implement prompt_file' do
      base_persona = described_class.new(context)
      expect { base_persona.prompt_file }.to raise_error(NotImplementedError)
    end

    it 'requires subclasses to implement available_tools' do
      base_persona = described_class.new(context)
      expect { base_persona.available_tools }.to raise_error(NotImplementedError)
    end

    it 'requires subclasses to implement fallback_responses' do
      base_persona = described_class.new(context)
      expect { base_persona.fallback_responses }.to raise_error(NotImplementedError)
    end

    it 'requires subclasses to implement offline_responses' do
      base_persona = described_class.new(context)
      expect { base_persona.offline_responses }.to raise_error(NotImplementedError)
    end
  end

  describe 'tool schema lazy loading' do
    let(:test_persona_class) do
      Class.new(described_class) do
        def self.name
          'TestPersona'
        end

        def prompt_file
          'test.txt'
        end

        def available_tools
          # Return class names as strings (simulating lazy loading)
          ['TestTool']
        end

        def fallback_responses
          ['Test fallback']
        end

        def offline_responses
          ['Test offline']
        end
      end
    end

    let(:persona) { test_persona_class.new({}) }

    it 'builds tool schemas lazily' do
      # Mock the tool loading to avoid requiring actual files
      allow(persona).to receive(:build_tool_schemas).and_return([])

      # First call builds schemas
      schemas1 = persona.tool_schemas
      # Second call uses memoized value
      schemas2 = persona.tool_schemas

      expect(schemas1).to equal(schemas2) # Same object reference
      expect(persona).to have_received(:build_tool_schemas).once
    end

    it 'returns empty array when no tools available' do
      allow(persona).to receive(:available_tools).and_return([])
      expect(persona.tool_schemas).to eq([])
    end
  end

  describe 'system prompt generation' do
    let(:test_persona_class) do
      Class.new(described_class) do
        def self.name
          'TestPersona'
        end

        def prompt_file
          'test.txt'
        end

        def available_tools
          []
        end

        def fallback_responses
          ['Test fallback']
        end

        def offline_responses
          ['Test offline']
        end
      end
    end

    let(:context) { { additional_context: 'Extra context info' } }
    let(:persona) { test_persona_class.new(context) }

    it 'includes datetime section' do
      prompt = persona.generate_system_prompt
      expect(prompt).to include('CURRENT DATE AND TIME')
      expect(prompt).to match(/Date: \w+, \w+ \d+, \d+/)
      expect(prompt).to match(/Time: \d+:\d+ [AP]M/)
    end

    it 'includes additional context when provided' do
      prompt = persona.generate_system_prompt
      expect(prompt).to include('ADDITIONAL CONTEXT')
      expect(prompt).to include('Extra context info')
    end

    it 'includes structured output section when response format is set' do
      persona_with_format = test_persona_class.new(context.merge(response_format: true))
      prompt = persona_with_format.generate_system_prompt
      expect(prompt).to include('RESPONSE FORMAT')
    end
  end
end
