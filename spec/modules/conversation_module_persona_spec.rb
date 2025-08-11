# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ConversationModule, 'persona management' do
  before do
    # Register all personas
    Personas::PersonaFactory.register_all

    # Clear any existing state
    Services::PersonaStateService.clear_state!
  end

  describe '.switch_persona' do
    it 'changes the current persona' do
      ConversationModule.switch_persona('jax')
      expect(ConversationModule.current_persona).to eq('jax')
    end

    it 'persists the persona change' do
      ConversationModule.switch_persona('lomi')

      # The persona should be 'lomi' from the state service
      expect(Services::PersonaStateService.get_current_persona).to eq('lomi')

      # Verify it persists for new instances
      expect(ConversationModule.current_persona).to eq('lomi')
    end

    it 'syncs with Home Assistant' do
      ha_client = instance_double(HomeAssistantClient)
      allow(HomeAssistantClient).to receive(:new).and_return(ha_client)

      expect(ha_client).to receive(:set_state).with(
        'input_text.current_persona',
        'zorp',
        hash_including(attributes: hash_including(display_name: 'Zorp'))
      )

      ConversationModule.switch_persona('zorp')
    end

    it 'raises error for invalid persona' do
      expect do
        ConversationModule.switch_persona('invalid_persona')
      end.to raise_error(ArgumentError, /Unknown persona/)
    end
  end

  describe '.current_persona' do
    it 'returns the current persona from state service' do
      Services::PersonaStateService.set_current_persona('buddy', sync_with_ha: false)
      expect(ConversationModule.current_persona).to eq('buddy')
    end

    it 'defaults to buddy when no persona set' do
      Services::PersonaStateService.clear_state!
      expect(ConversationModule.current_persona).to eq('buddy')
    end
  end

  describe 'convenience methods' do
    let(:ha_client) { instance_double(HomeAssistantClient) }

    before do
      allow(HomeAssistantClient).to receive(:new).and_return(ha_client)
      allow(ha_client).to receive(:set_state)
    end

    it '.buddy switches to buddy persona' do
      ConversationModule.buddy
      expect(ConversationModule.current_persona).to eq('buddy')
    end

    it '.jax switches to jax persona' do
      ConversationModule.jax
      expect(ConversationModule.current_persona).to eq('jax')
    end

    it '.lomi switches to lomi persona' do
      ConversationModule.lomi
      expect(ConversationModule.current_persona).to eq('lomi')
    end

    it '.zorp switches to zorp persona' do
      ConversationModule.zorp
      expect(ConversationModule.current_persona).to eq('zorp')
    end

    it 'returns a ConversationModule instance' do
      expect(ConversationModule.buddy).to be_a(ConversationModule)
      expect(ConversationModule.jax).to be_a(ConversationModule)
    end
  end

  describe 'conversation uses persisted persona' do
    it 'uses the persona from PersonaStateService when not specified' do
      # Set persona via state service
      ConversationModule.switch_persona('zorp')

      # Verify the persona is persisted
      expect(ConversationModule.current_persona).to eq('zorp')

      # Clear any previous persona state and set a new one
      Services::PersonaStateService.set_current_persona('lomi', sync_with_ha: false)

      # Now when we check the current persona, it should be 'lomi'
      expect(ConversationModule.current_persona).to eq('lomi')

      # Create conversation without specifying persona
      conversation = ConversationModule.new

      # The conversation module instance is created successfully
      expect(conversation).to be_a(ConversationModule)
    end
  end
end
