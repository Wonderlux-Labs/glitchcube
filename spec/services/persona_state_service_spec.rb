# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/persona_state_service'
require_relative '../../lib/personas/persona_factory'
require_relative '../../lib/personas/base_persona'
require_relative '../../lib/personas/buddy_persona'

RSpec.describe Services::PersonaStateService do
  include_context 'with_home_assistant_entities'
  include_context 'with_clean_redis'

  before do
    # Register personas for testing
    Personas::PersonaFactory.register_all

    # Mock the logger to prevent noise
    allow(Services::Logging::SimpleLogger).to receive(:info)
    allow(Services::Logging::SimpleLogger).to receive(:debug)
    allow(Services::Logging::SimpleLogger).to receive(:log_error)
  end

  describe '.get_current_persona' do
    it 'returns default persona when no specific persona is set' do
      result = described_class.get_current_persona
      expect(result).to eq('buddy')
    end

    it 'returns the currently set persona' do
      # Set a persona first
      described_class.set_current_persona('jax')

      result = described_class.get_current_persona
      expect(result).to eq('jax')
    end
  end

  describe '.set_current_persona' do
    it 'returns the normalized persona name' do
      result = described_class.set_current_persona('jax')
      expect(result).to eq('jax')
    end

    it 'syncs with Home Assistant by default' do
      expect(ha_client).to receive(:set_state).with(
        'input_text.current_persona',
        'jax',
        hash_including(attributes: hash_including(friendly_name: 'Current AI Persona'))
      ).and_return(true)

      result = described_class.set_current_persona('jax')
      expect(result).to eq('jax')
    end

    it 'skips Home Assistant sync when requested' do
      expect(ha_client).not_to receive(:set_state)

      result = described_class.set_current_persona('jax', sync_with_ha: false)
      expect(result).to eq('jax')
    end

    it 'normalizes persona names to lowercase' do
      result = described_class.set_current_persona('BUDDY')
      expect(result).to eq('buddy')
    end

    it 'persists the persona setting' do
      described_class.set_current_persona('jax')

      result = described_class.get_current_persona
      expect(result).to eq('jax')
    end

    it 'raises error for unknown persona' do
      expect do
        described_class.set_current_persona('unknown_persona')
      end.to raise_error(ArgumentError, /Unknown persona/)
    end
  end

  describe '.sync_with_home_assistant' do
    it 'updates Home Assistant entity with current persona' do
      # Set a persona first
      described_class.set_current_persona('lomi', sync_with_ha: false)

      expect(ha_client).to receive(:set_state).with(
        'input_text.current_persona',
        'lomi',
        hash_including(
          attributes: hash_including(
            icon: 'mdi:robot',
            friendly_name: 'Current AI Persona'
          )
        )
      )

      expect(described_class.sync_with_home_assistant).to be true
    end

    it 'returns false on Home Assistant error' do
      allow(ha_client).to receive(:set_state).and_raise(StandardError)

      expect(described_class.sync_with_home_assistant).to be false
    end
  end

  describe '.get_persona_from_home_assistant' do
    it 'returns persona from Home Assistant state' do
      allow(ha_client).to receive(:state).with('input_text.current_persona')
                                         .and_return({ 'state' => 'Zorp' })

      expect(described_class.get_persona_from_home_assistant).to eq('zorp')
    end

    it 'returns default when Home Assistant state is unavailable' do
      allow(ha_client).to receive(:state).with('input_text.current_persona')
                                         .and_return({ 'state' => 'unavailable' })

      expect(described_class.get_persona_from_home_assistant).to eq('buddy')
    end

    it 'returns default on Home Assistant error' do
      allow(ha_client).to receive(:state).and_raise(StandardError)

      expect(described_class.get_persona_from_home_assistant).to eq('buddy')
    end
  end

  describe '.sync_from_home_assistant' do
    it 'updates persona from Home Assistant without syncing back' do
      allow(ha_client).to receive(:state).with('input_text.current_persona')
                                         .and_return({ 'state' => 'Jax' })

      # Should sync the persona internally without triggering another HA call
      expect(ha_client).not_to receive(:set_state)

      described_class.sync_from_home_assistant

      # Verify the persona was updated
      expect(described_class.get_current_persona).to eq('jax')
    end
  end

  describe '.get_usage_stats' do
    it 'returns usage statistics as a hash' do
      # Use personas to generate some stats
      described_class.set_current_persona('buddy')
      described_class.set_current_persona('jax')
      described_class.set_current_persona('jax')  # jax used twice

      stats = described_class.get_usage_stats

      expect(stats).to be_a(Hash)
      expect(stats.keys).to include('buddy', 'jax')
    end

    it 'handles the case when no stats are available' do
      stats = described_class.get_usage_stats
      expect(stats).to be_a(Hash)
    end
  end

  describe '.clear_state!' do
    it 'clears persona state successfully' do
      # Set some state first
      described_class.set_current_persona('jax')
      expect(described_class.get_current_persona).to eq('jax')

      # Clear the state
      result = described_class.clear_state!
      expect(result).to be true

      # Verify state was cleared (should return to default)
      expect(described_class.get_current_persona).to eq('buddy')
    end
  end
end
