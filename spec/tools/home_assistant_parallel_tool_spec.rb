# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/tools/home_assistant_parallel_tool'

RSpec.describe HomeAssistantParallelTool do
  let(:mock_client) { instance_double(HomeAssistantClient) }

  before do
    allow(HomeAssistantClient).to receive(:new).and_return(mock_client)
  end

  describe '.call' do
    context 'with multiple actions' do
      let(:actions) do
        [
          { 'action' => 'get_sensor', 'params' => { 'entity_id' => 'sensor.temperature' } },
          { 'action' => 'set_light', 'params' => { 'entity_id' => 'light.test', 'brightness' => 50 } },
          { 'action' => 'speak', 'params' => { 'message' => 'Hello world' } }
        ]
      end

      it 'executes all actions in parallel' do
        allow(mock_client).to receive(:state).with('sensor.temperature').and_return(
          { 'state' => '22.5', 'attributes' => { 'unit_of_measurement' => '°C' } }
        )
        allow(mock_client).to receive(:set_light).with('light.test', brightness: 50, rgb_color: nil).and_return(true)
        allow(mock_client).to receive(:speak).with('Hello world', entity_id: 'media_player.square_voice').and_return(true)

        result = described_class.call(actions: actions)

        expect(result).to include('✅ Completed 3 actions:')
        expect(result).to include('sensor.temperature: 22.5°C')
        expect(result).to include('Spoke: "Hello world"')
      end

      it 'handles partial failures gracefully' do
        allow(mock_client).to receive(:state).and_raise('Sensor not found')
        allow(mock_client).to receive(:set_light).and_return(true)
        allow(mock_client).to receive(:speak).and_return(true)

        result = described_class.call(actions: actions)

        expect(result).to include('✅ Completed 2 actions:')
        expect(result).to include('⚠️ Failed 1 actions:')
      end

      it 'handles timeout for slow actions' do
        allow(mock_client).to receive(:state) do
          sleep(4) # Exceed 3 second timeout
          { 'state' => '22.5' }
        end
        allow(mock_client).to receive(:set_light).and_return(true)
        allow(mock_client).to receive(:speak).and_return(true)

        result = described_class.call(actions: actions)

        expect(result).to include('Action 0 timed out')
      end
    end

    context 'with AWTRIX display action' do
      let(:actions) do
        [{ 'action' => 'awtrix_display', 'params' => { 'text' => 'Test', 'color' => [255, 0, 0] } }]
      end

      it 'sends text to AWTRIX display' do
        expect(mock_client).to receive(:awtrix_display_text).with(
          'Test',
          color: [255, 0, 0],
          duration: 5,
          rainbow: false
        ).and_return(true)

        result = described_class.call(actions: actions)

        expect(result).to include('✅ Completed 1 actions:')
      end
    end

    context 'with JSON string input' do
      let(:actions_json) { '[{"action":"get_sensor","params":{"entity_id":"sensor.test"}}]' }

      it 'parses JSON string actions' do
        allow(mock_client).to receive(:state).and_return({ 'state' => '100' })

        result = described_class.call(actions: actions_json)

        expect(result).to include('✅ Completed 1 actions:')
      end
    end

    context 'with single action (not array)' do
      let(:single_action) { { 'action' => 'speak', 'params' => { 'message' => 'Test' } } }

      it 'wraps single action in array' do
        allow(mock_client).to receive(:speak).and_return(true)

        result = described_class.call(actions: single_action)

        expect(result).to include('✅ Completed 1 actions:')
      end
    end
  end
end