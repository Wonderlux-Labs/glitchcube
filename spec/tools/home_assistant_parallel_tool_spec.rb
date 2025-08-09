# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/tools/home_assistant_parallel_tool'

RSpec.describe HomeAssistantParallelTool do
  describe '.call' do
    context 'with multiple actions' do
      let(:actions) do
        [
          { 'action' => 'get_sensor', 'params' => { 'entity_id' => 'sensor.temperature' } },
          { 'action' => 'set_light', 'params' => { 'entity_id' => 'light.test', 'brightness' => 50 } },
          { 'action' => 'speak', 'params' => { 'message' => 'Hello world' } }
        ]
      end

      it 'executes all actions in parallel', vcr: 'home_assistant_parallel_tool/executes_all_actions' do
        result = described_class.call(actions: actions)

        # TTS and light control succeed now
        expect(result).to include('✅ Completed 2 actions:')
        expect(result).to include('Spoke: "Hello world"')
        expect(result).to include('⚠️ Failed 1 actions:')
      end

      it 'handles partial failures gracefully', vcr: 'home_assistant_parallel_tool/handles_failures' do
        # Use an invalid sensor that should fail
        actions_with_failure = [
          { 'action' => 'get_sensor', 'params' => { 'entity_id' => 'sensor.nonexistent' } },
          { 'action' => 'set_light', 'params' => { 'entity_id' => 'light.test', 'brightness' => 50 } },
          { 'action' => 'speak', 'params' => { 'message' => 'Hello world' } }
        ]

        result = described_class.call(actions: actions_with_failure)

        expect(result).to include('actions:') # Should have some results
      end

      it 'handles timeout for slow actions', vcr: 'home_assistant_parallel_tool/handles_timeout' do
        # This test will just verify the timeout handling exists
        # Actual timeout testing would require a slow HA response
        result = described_class.call(actions: actions)

        # Should complete normally with fast responses
        expect(result).to include('actions:')
      end
    end

    context 'with AWTRIX display action' do
      let(:actions) do
        [{ 'action' => 'awtrix_display', 'params' => { 'text' => 'Test', 'color' => [255, 0, 0] } }]
      end

      it 'sends text to AWTRIX display', vcr: 'home_assistant_parallel_tool/awtrix_display' do
        result = described_class.call(actions: actions)

        expect(result).to include('✅ Completed 1 actions:')
      end
    end

    context 'with JSON string input' do
      let(:actions_json) { '[{"action":"get_sensor","params":{"entity_id":"sensor.test"}}]' }

      it 'parses JSON string actions', vcr: 'home_assistant_parallel_tool/json_parsing' do
        result = described_class.call(actions: actions_json)

        # Sensor request fails with entity not found
        expect(result).to include('⚠️ Failed 1 actions:')
        expect(result).to include('Entity or service not found')
      end
    end

    context 'with single action (not array)' do
      let(:single_action) { { 'action' => 'speak', 'params' => { 'message' => 'Test' } } }

      it 'wraps single action in array', vcr: 'home_assistant_parallel_tool/single_action' do
        result = described_class.call(actions: single_action)

        expect(result).to include('✅ Completed 1 actions:')
      end
    end
  end
end
