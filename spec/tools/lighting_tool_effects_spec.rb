# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Tools::LightingTool do
  include_context 'with_home_assistant_stubbed'

  let(:entity_id) { 'light.cube_light' }
  let(:effect_list) { %w[none sunrise sunset movie dating romantic twinkle candlelight snowflake energetic breathe crossing] }

  let(:ha_state_response) do
    {
      'state' => 'on',
      'attributes' => {
        'effect_list' => effect_list,
        'effect' => 'none',
        'brightness' => 255,
        'color_mode' => 'rgb'
      }
    }
  end

  before do
    allow(Core::HomeAssistantClient).to receive(:new).and_return(ha_client)
  end

  describe '.list_effects' do
    context 'with valid entity that supports effects' do
      before do
        allow(ha_client).to receive(:state).with(entity_id).and_return(ha_state_response)
      end

      it 'returns available effects for the entity' do
        result = described_class.list_effects(entity_id: entity_id)

        expect(result).to start_with('✅')
        expect(result).to include("Available effects for #{entity_id}")
        expect(result).to include('Data:')
        expect(result).to include('entity_id')
        expect(result).to include('effects')
      end
    end

    context 'with entity that does not support effects' do
      let(:ha_state_no_effects) do
        {
          'state' => 'on',
          'attributes' => {
            'brightness' => 255,
            'color_mode' => 'rgb'
            # No effect_list
          }
        }
      end

      before do
        allow(ha_client).to receive(:state).with(entity_id).and_return(ha_state_no_effects)
      end

      it 'returns error message' do
        result = described_class.list_effects(entity_id: entity_id)

        expect(result).to start_with('❌')
        expect(result).to include("No effects available for #{entity_id}")
      end
    end

    context 'with non-existent entity' do
      before do
        allow(ha_client).to receive(:state).with(entity_id).and_return(nil)
      end

      it 'returns entity not found error' do
        result = described_class.list_effects(entity_id: entity_id)

        expect(result).to start_with('❌')
        expect(result).to include('Entity light.cube_light not found')
      end
    end

    context 'with target name conversion' do
      it 'converts "cube" to "light.cube_light"' do
        allow(ha_client).to receive(:state).with('light.cube_light').and_return(ha_state_response)

        result = described_class.list_effects(entity_id: 'cube')

        expect(result).to include('success' => true)
        expect(result['data']).to include('entity_id' => 'light.cube_light')
      end

      it 'finds partial matches in entity names' do
        allow(ha_client).to receive(:state).with('light.cube_light').and_return(ha_state_response)

        result = described_class.list_effects(entity_id: 'cube_light')

        expect(result).to include('success' => true)
        expect(result['data']).to include('entity_id' => 'light.cube_light')
      end
    end
  end

  describe '.set_effect' do
    let(:valid_effect) { 'romantic' }
    let(:invalid_effect) { 'invalid_effect' }

    context 'with valid entity and effect' do
      before do
        allow(ha_client).to receive(:state).with(entity_id).and_return(ha_state_response)
        mock_ha_service_call('light.turn_on', { entity_id: entity_id, effect: valid_effect })
      end

      it 'sets the effect successfully' do
        result = described_class.set_effect(entity_id: entity_id, effect: valid_effect)

        expect(result).to include('success' => true)
        expect(result).to include('message' => "Set #{entity_id} effect to #{valid_effect}")

        expect(ha_client).to have_received(:call_service).with(
          'light',
          'turn_on',
          { entity_id: entity_id, effect: valid_effect }
        )
      end
    end

    context 'with invalid effect' do
      before do
        allow(ha_client).to receive(:state).with(entity_id).and_return(ha_state_response)
      end

      it 'returns error with available effects list' do
        result = described_class.set_effect(entity_id: entity_id, effect: invalid_effect)

        expect(result).to include('success' => false)
        expect(result['message']).to include("Effect 'invalid_effect' not available")
        expect(result['message']).to include('Available: none, sunrise, sunset')
      end
    end

    context 'with entity that does not support effects' do
      let(:ha_state_no_effects) do
        {
          'state' => 'on',
          'attributes' => {
            'brightness' => 255,
            'color_mode' => 'rgb'
            # No effect_list
          }
        }
      end

      before do
        allow(ha_client).to receive(:state).with(entity_id).and_return(ha_state_no_effects)
      end

      it 'returns error message' do
        result = described_class.set_effect(entity_id: entity_id, effect: valid_effect)

        expect(result).to include('success' => false)
        expect(result).to include('message' => "#{entity_id} does not support effects")
      end
    end

    context 'with target name conversion' do
      before do
        allow(ha_client).to receive(:state).with('light.cube_light').and_return(ha_state_response)
        mock_ha_service_call('light.turn_on', { entity_id: 'light.cube_light', effect: valid_effect })
      end

      it 'converts "cube" to "light.cube_light"' do
        result = described_class.set_effect(entity_id: 'cube', effect: valid_effect)

        expect(result).to include('success' => true)
        expect(result).to include('message' => 'Set light.cube_light effect to romantic')
      end
    end

    context 'when Home Assistant service call fails' do
      before do
        allow(ha_client).to receive(:state).with(entity_id).and_return(ha_state_response)
        allow(ha_client).to receive(:call_service).and_raise(StandardError.new('HA connection failed'))
      end

      it 'returns error message' do
        result = described_class.set_effect(entity_id: entity_id, effect: valid_effect)

        expect(result).to include('success' => false)
        expect(result['message']).to include('Failed to set effect')
        expect(result['message']).to include('HA connection failed')
      end
    end
  end

  describe '.convert_target_to_entity_id' do
    it 'converts known targets to entity IDs' do
      expect(described_class.convert_target_to_entity_id('cube')).to eq('light.cube_light')
      expect(described_class.convert_target_to_entity_id('cart')).to eq('light.cart_light')
      expect(described_class.convert_target_to_entity_id('matrix')).to eq('light.awtrix_b85e20_matrix')
    end

    it 'returns entity IDs as-is' do
      expect(described_class.convert_target_to_entity_id('light.cube_light')).to eq('light.cube_light')
    end

    it 'finds partial matches in entity names' do
      expect(described_class.convert_target_to_entity_id('cube_light')).to eq('light.cube_light')
      expect(described_class.convert_target_to_entity_id('cart_light')).to eq('light.cart_light')
    end

    it 'returns first entity for groups' do
      expect(described_class.convert_target_to_entity_id('all')).to eq('light.cube_light')
      expect(described_class.convert_target_to_entity_id('ambient')).to eq('light.cube_light')
    end

    it 'returns unknown targets as-is' do
      expect(described_class.convert_target_to_entity_id('unknown_target')).to eq('unknown_target')
    end
  end
end
