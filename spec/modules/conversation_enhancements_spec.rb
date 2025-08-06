# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/modules/conversation_enhancements'

class TestClass
  include ConversationEnhancements
end

RSpec.describe ConversationEnhancements do
  let(:test_instance) { TestClass.new }

  describe '#execute_parallel_tools' do
    let(:tool_calls) do
      [
        {
          function: {
            name: 'home_assistant',
            arguments: '{"action": "get_sensors"}'
          }
        },
        {
          function: {
            name: 'test_tool',
            arguments: '{"message": "test"}'
          }
        }
      ]
    end

    before do
      allow(test_instance).to receive(:find_tool_class).with('home_assistant').and_return(HomeAssistantTool)
      allow(test_instance).to receive(:find_tool_class).with('test_tool').and_return(TestTool)
      allow(HomeAssistantTool).to receive(:call).and_return('Sensor data')
      allow(TestTool).to receive(:call).and_return('Test result')
    end

    it 'executes all tools in parallel' do
      results = test_instance.execute_parallel_tools(tool_calls)

      expect(results).to have(2).items
      expect(results[0]).to include(tool: 'home_assistant', success: true)
      expect(results[1]).to include(tool: 'test_tool', success: true)
    end

    it 'handles tool timeouts' do
      allow(HomeAssistantTool).to receive(:call) do
        sleep(6) # Exceed 5 second timeout
        'Should timeout'
      end

      results = test_instance.execute_parallel_tools(tool_calls)

      expect(results).not_to be_empty
      expect(results[0]).to include(
        tool: 'home_assistant',
        error: 'Tool execution timed out'
      )
    end

    it 'returns empty array for nil input' do
      result = test_instance.execute_parallel_tools(nil)
      expect(result).to eq([])
    end
  end

  describe '#execute_with_retry' do
    it 'succeeds on first attempt' do
      attempt_count = 0
      
      result = test_instance.execute_with_retry(3) do
        attempt_count += 1
        'success'
      end

      expect(result).to eq('success')
      expect(attempt_count).to eq(1)
    end

    it 'retries with exponential backoff' do
      attempt_count = 0
      
      allow(test_instance).to receive(:sleep).with(0.5).once
      allow(test_instance).to receive(:sleep).with(1.0).once

      result = test_instance.execute_with_retry(3) do
        attempt_count += 1
        if attempt_count < 3
          raise 'Temporary error'
        else
          'success'
        end
      end

      expect(result).to eq('success')
      expect(attempt_count).to eq(3)
    end

    it 'raises error after max attempts' do
      expect do
        test_instance.execute_with_retry(2) do
          raise 'Persistent error'
        end
      end.to raise_error('Persistent error')
    end
  end

  describe '#enrich_context_with_sensors' do
    let(:mock_client) { instance_double(HomeAssistantClient) }
    let(:context) { { include_sensors: true } }

    before do
      allow(HomeAssistantClient).to receive(:new).and_return(mock_client)
    end

    it 'enriches context with sensor data' do
      allow(mock_client).to receive(:battery_level).and_return(85)
      allow(mock_client).to receive(:temperature).and_return(22.5)
      allow(mock_client).to receive(:motion_detected?).and_return(false)

      enriched = test_instance.enrich_context_with_sensors(context)

      expect(enriched[:sensor_data]).to include(
        battery: 85,
        temperature: 22.5,
        motion: false
      )
      expect(enriched[:sensor_summary]).to eq('Battery: 85%, Temp: 22.5°C, Motion: none')
    end

    it 'handles sensor failures gracefully' do
      allow(mock_client).to receive(:battery_level).and_raise('Sensor error')
      allow(mock_client).to receive(:temperature).and_return(22.5)
      allow(mock_client).to receive(:motion_detected?).and_return(true)

      enriched = test_instance.enrich_context_with_sensors(context)

      expect(enriched[:sensor_data][:battery]).to be_nil
      expect(enriched[:sensor_data][:temperature]).to eq(22.5)
    end

    it 'skips enrichment when not requested' do
      plain_context = { other: 'data' }
      
      result = test_instance.enrich_context_with_sensors(plain_context)
      
      expect(result[:sensor_data]).to be_nil
    end
  end

  describe '#attempt_error_recovery' do
    it 'attempts connection recovery for connection errors' do
      expect(test_instance).to receive(:attempt_connection_recovery).and_return(true)
      
      result = test_instance.attempt_error_recovery('connection refused')
      expect(result).to be true
    end

    it 'attempts timeout recovery for timeout errors' do
      expect(test_instance).to receive(:attempt_timeout_recovery).and_return(true)
      
      result = test_instance.attempt_error_recovery('timeout error')
      expect(result).to be true
    end

    it 'attempts rate limit recovery' do
      expect(test_instance).to receive(:attempt_rate_limit_recovery).and_return(true)
      
      result = test_instance.attempt_error_recovery('rate limit exceeded')
      expect(result).to be true
    end

    it 'returns false for unknown errors' do
      result = test_instance.attempt_error_recovery('unknown error')
      expect(result).to be false
    end
  end

  describe '#with_self_healing' do
    it 'succeeds without retries when operation works' do
      result = test_instance.with_self_healing('test_operation') do
        'success'
      end

      expect(result).to eq('success')
    end

    it 'attempts auto-recovery on failure' do
      attempt_count = 0
      
      expect(test_instance).to receive(:attempt_error_recovery).with(
        'network error',
        { operation: 'test_operation' }
      ).and_return(true)

      result = test_instance.with_self_healing('test_operation', max_retries: 2) do
        attempt_count += 1
        if attempt_count == 1
          raise 'network error'
        else
          'recovered'
        end
      end

      expect(result).to eq('recovered')
    end

    it 'uses exponential backoff when auto-recovery fails' do
      attempt_count = 0
      
      expect(test_instance).to receive(:attempt_error_recovery).and_return(false)
      expect(test_instance).to receive(:sleep).with(2).once # 2^(2-1) = 2

      result = test_instance.with_self_healing('test_operation', max_retries: 2) do
        attempt_count += 1
        if attempt_count == 1
          raise 'error'
        else
          'success'
        end
      end

      expect(result).to eq('success')
    end

    it 'raises error after all retries exhausted' do
      expect(test_instance).to receive(:attempt_error_recovery).once.and_return(false)
      expect(test_instance).to receive(:sleep).once # Only one sleep since second retry will fail

      expect do
        test_instance.with_self_healing('test_operation', max_retries: 2) do
          raise 'persistent error'
        end
      end.to raise_error('persistent error')
    end
  end
end