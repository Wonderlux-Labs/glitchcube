# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/persona_state_service'
require_relative '../../lib/personas/persona_factory'
require_relative '../../lib/personas/base_persona'
require_relative '../../lib/personas/buddy_persona'

RSpec.describe Services::PersonaStateService do
  let(:redis_client) { instance_double(Redis) }
  let(:ha_client) { instance_double(Core::HomeAssistantClient) }
  let(:config_double) { instance_double('Config', redis_url: 'redis://localhost:6379/0') }

  before do
    # Reset any cached instance variables to ensure clean state for each test
    described_class.instance_variable_set(:@redis_client, nil)
    described_class.instance_variable_set(:@redis_available, nil)

    # Mock the configuration
    allow(GlitchCube).to receive(:config).and_return(config_double)

    allow(Core::HomeAssistantClient).to receive(:new).and_return(ha_client)

    # Register personas for testing - this will set up the actual persona registry
    Personas::PersonaFactory.register_all

    # Mock the logger to prevent noise
    allow(Services::Logging::SimpleLogger).to receive(:info)
    allow(Services::Logging::SimpleLogger).to receive(:debug)
    allow(Services::Logging::SimpleLogger).to receive(:log_error)
  end

  describe '.get_current_persona' do
    context 'when Redis is available' do
      before do
        allow(described_class).to receive(:redis_available?).and_return(true)
        allow(described_class).to receive(:redis_client).and_return(redis_client)
      end

      it 'returns the stored persona' do
        expect(redis_client).to receive(:get).with('glitchcube:current_persona').and_return('jax')

        result = described_class.get_current_persona
        expect(result).to eq('jax')
      end

      it 'returns default persona when none is stored' do
        allow(redis_client).to receive(:get).with('glitchcube:current_persona').and_return(nil)

        expect(described_class.get_current_persona).to eq('buddy')
      end

      it 'returns default persona on Redis error' do
        allow(redis_client).to receive(:get).and_raise(Redis::ConnectionError)

        expect(described_class.get_current_persona).to eq('buddy')
      end
    end

    context 'when Redis is not available' do
      before do
        # Override Redis availability for this context
        allow(described_class).to receive(:redis_available?).and_return(false)
      end

      it 'returns default persona' do
        expect(described_class.get_current_persona).to eq('buddy')
      end
    end
  end

  describe '.set_current_persona' do
    context 'with valid persona' do
      before do
        allow(described_class).to receive(:redis_available?).and_return(true)
        allow(described_class).to receive(:redis_client).and_return(redis_client)
        allow(redis_client).to receive(:set).and_return('OK')
        allow(redis_client).to receive(:incr).and_return(1)
        allow(redis_client).to receive(:expire).and_return(1)
        allow(ha_client).to receive(:set_state).and_return(true)
      end

      it 'stores persona in Redis' do
        expect(redis_client).to receive(:set).with('glitchcube:current_persona', 'jax', ex: 86_400)

        result = described_class.set_current_persona('jax')
        expect(result).to eq('jax')  # Ensure service returns the normalized name
      end

      it 'increments usage stats' do
        expect(redis_client).to receive(:incr).with('glitchcube:persona_stats:jax')
        expect(redis_client).to receive(:expire).with('glitchcube:persona_stats:jax', 30 * 86_400)

        described_class.set_current_persona('jax')
      end

      it 'syncs with Home Assistant by default' do
        expect(ha_client).to receive(:set_state).with(
          'input_text.current_persona',
          'jax',
          hash_including(attributes: hash_including(friendly_name: 'Current AI Persona'))
        )

        described_class.set_current_persona('jax')
      end

      it 'skips Home Assistant sync when requested' do
        expect(ha_client).not_to receive(:set_state)

        described_class.set_current_persona('jax', sync_with_ha: false)
      end

      it 'normalizes persona names' do
        expect(redis_client).to receive(:set).with('glitchcube:current_persona', 'buddy', ex: 86_400)

        described_class.set_current_persona('BUDDY')
      end
    end

    context 'with invalid persona' do
      before do
        allow(described_class).to receive(:redis_available?).and_return(true)
        allow(described_class).to receive(:redis_client).and_return(redis_client)
        allow(redis_client).to receive(:set).and_return('OK')
        allow(redis_client).to receive(:incr).and_return(1)
        allow(redis_client).to receive(:expire).and_return(1)
        allow(ha_client).to receive(:set_state).and_return(true)
      end

      it 'raises error for unknown persona' do
        expect do
          described_class.set_current_persona('unknown_persona')
        end.to raise_error(ArgumentError, /Unknown persona/)
      end
    end

    context 'when Redis is not available' do
      before do
        # Override Redis availability for this context
        allow(described_class).to receive(:redis_available?).and_return(false)
        allow(ha_client).to receive(:set_state).and_return(true)
      end

      it 'still syncs with Home Assistant' do
        expect(ha_client).to receive(:set_state).with(
          'input_text.current_persona',
          'jax',
          hash_including(
            attributes: hash_including(
              friendly_name: 'Current AI Persona',
              icon: 'mdi:robot'
            )
          )
        )

        described_class.set_current_persona('jax')
      end
    end
  end

  describe '.sync_with_home_assistant' do
    before do
      allow(ha_client).to receive(:set_state).and_return(true)
    end

    it 'updates Home Assistant entity with current persona' do
      allow(described_class).to receive(:get_current_persona).and_return('lomi')

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
      allow(described_class).to receive(:get_current_persona).and_return('buddy')
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
    it 'updates Redis with Home Assistant persona without syncing back' do
      allow(described_class).to receive(:get_persona_from_home_assistant).and_return('jax')
      expect(described_class).to receive(:set_current_persona).with('jax', sync_with_ha: false)

      described_class.sync_from_home_assistant
    end
  end

  describe '.get_usage_stats' do
    context 'when Redis is available' do
      before do
        allow(described_class).to receive(:redis_available?).and_return(true)
        allow(described_class).to receive(:redis_client).and_return(redis_client)
      end

      it 'returns usage statistics for all personas' do
        allow(redis_client).to receive(:get).with('glitchcube:persona_stats:buddy').and_return('10')
        allow(redis_client).to receive(:get).with('glitchcube:persona_stats:jax').and_return('5')
        allow(redis_client).to receive(:get).with('glitchcube:persona_stats:lomi').and_return('0')
        allow(redis_client).to receive(:get).with('glitchcube:persona_stats:zorp').and_return('3')

        stats = described_class.get_usage_stats

        expect(stats).to eq({
                              'buddy' => 10,
                              'jax' => 5,
                              'zorp' => 3
                            })
      end
    end

    context 'when Redis is not available' do
      before do
        allow(described_class).to receive(:redis_available?).and_return(false)
      end

      it 'returns empty hash when Redis is not available' do
        expect(described_class.get_usage_stats).to eq({})
      end
    end
  end

  describe '.clear_state!' do
    context 'when Redis is available' do
      before do
        allow(described_class).to receive(:redis_available?).and_return(true)
        allow(described_class).to receive(:redis_client).and_return(redis_client)
      end

      it 'clears persona state and stats from Redis' do
        allow(redis_client).to receive(:keys).with('glitchcube:persona_stats:*')
                                             .and_return(['glitchcube:persona_stats:buddy', 'glitchcube:persona_stats:jax'])

        expect(redis_client).to receive(:del).with('glitchcube:current_persona')
        expect(redis_client).to receive(:del).with('glitchcube:persona_stats:buddy', 'glitchcube:persona_stats:jax')

        expect(described_class.clear_state!).to be true
      end

      it 'handles case when no stats keys exist' do
        allow(redis_client).to receive(:keys).with('glitchcube:persona_stats:*').and_return([])

        expect(redis_client).to receive(:del).with('glitchcube:current_persona')
        expect(redis_client).not_to receive(:del).with(no_args)

        expect(described_class.clear_state!).to be true
      end
    end

    context 'when Redis is not available' do
      before do
        allow(described_class).to receive(:redis_available?).and_return(false)
      end

      it 'returns true when Redis is not available' do
        expect(described_class.clear_state!).to be true
      end
    end
  end
end
