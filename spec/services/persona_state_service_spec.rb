# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/persona_state_service'
require_relative '../../lib/personas/persona_factory'
require_relative '../../lib/personas/base_persona'
require_relative '../../lib/personas/buddy_persona'
require_relative '../../lib/personas/jax_persona'
require_relative '../../lib/personas/lomi_persona'
require_relative '../../lib/personas/zorp_persona'

RSpec.describe Services::PersonaStateService do
  include_context 'with_home_assistant_entities'
  include_context 'with_clean_redis'

  let(:mock_redis) { instance_double(Redis) }
  let(:mock_config) { double('Config', redis_url: 'redis://localhost:6379/0') }

  before do
    # Register personas for testing
    Personas::PersonaFactory.register_all

    # Clear memoized instance variables to ensure clean state
    Services::PersonaStateService.instance_variable_set(:@redis_client, nil)
    Services::PersonaStateService.instance_variable_set(:@redis_available, nil)

    # Mock GlitchCube.config to return a redis_url
    allow(GlitchCube).to receive(:config).and_return(mock_config)

    # Mock Redis client and make it available
    allow(Redis).to receive(:new).and_return(mock_redis)
    allow(mock_redis).to receive(:ping).and_return('PONG')
    allow(mock_redis).to receive(:get).and_return(nil)
    allow(mock_redis).to receive(:set).and_return(true)
    allow(mock_redis).to receive(:incr).and_return(1)
    allow(mock_redis).to receive(:expire).and_return(true)
    allow(mock_redis).to receive(:del).and_return(1)
    allow(mock_redis).to receive(:keys).and_return([])

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
      # Mock Redis to return 'jax' when get is called
      allow(mock_redis).to receive(:get).with('glitchcube:current_persona').and_return('jax')

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
        hash_including(
          attributes: hash_including(
            friendly_name: 'Current AI Persona',
            icon: 'mdi:robot'
          )
        )
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
      # Set up Redis to return the persona after it's set
      allow(mock_redis).to receive(:get).with('glitchcube:current_persona').and_return('jax')

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
      # Mock Redis to return 'lomi' as current persona
      allow(mock_redis).to receive(:get).with('glitchcube:current_persona').and_return('lomi')

      expect(ha_client).to receive(:set_state).with(
        'input_text.current_persona',
        'lomi',
        hash_including(
          attributes: hash_including(
            icon: 'mdi:robot',
            friendly_name: 'Current AI Persona'
          )
        )
      ).and_return(true)

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

      # Mock Redis to return 'jax' after the sync
      allow(mock_redis).to receive(:get).with('glitchcube:current_persona').and_return('jax')

      described_class.sync_from_home_assistant

      # Verify the persona was updated
      expect(described_class.get_current_persona).to eq('jax')
    end
  end

  describe '.get_usage_stats' do
    it 'returns usage statistics as a hash' do
      # Mock Redis to return stats for personas
      allow(mock_redis).to receive(:get).with('glitchcube:persona_stats:buddy').and_return('1')
      allow(mock_redis).to receive(:get).with('glitchcube:persona_stats:jax').and_return('2')
      allow(mock_redis).to receive(:get).with('glitchcube:persona_stats:lomi').and_return('0')
      allow(mock_redis).to receive(:get).with('glitchcube:persona_stats:zorp').and_return('0')

      stats = described_class.get_usage_stats

      expect(stats).to be_a(Hash)
      expect(stats.keys).to include('buddy', 'jax')
      expect(stats['buddy']).to eq(1)
      expect(stats['jax']).to eq(2)
    end

    it 'handles the case when no stats are available' do
      # Mock Redis to return '0' for all stats (which will be filtered out)
      allow(mock_redis).to receive(:get).and_return('0')

      stats = described_class.get_usage_stats
      expect(stats).to be_a(Hash)
      expect(stats).to be_empty
    end
  end

  describe '.clear_state!' do
    it 'clears persona state successfully' do
      # Initially mock Redis to return 'jax'
      allow(mock_redis).to receive(:get).with('glitchcube:current_persona').and_return('jax')
      expect(described_class.get_current_persona).to eq('jax')

      # Clear the state
      result = described_class.clear_state!
      expect(result).to be true

      # After clearing, mock Redis to return nil (cleared)
      allow(mock_redis).to receive(:get).with('glitchcube:current_persona').and_return(nil)

      # Verify state was cleared (should return to default)
      expect(described_class.get_current_persona).to eq('buddy')
    end
  end
end
