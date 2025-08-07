# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/modules/conversation_enhancements'

class TestClass
  include ConversationEnhancements
end

RSpec.describe ConversationEnhancements do
  let(:test_instance) { TestClass.new }

  describe '#format_sensor_summary' do
    it 'formats sensor data correctly' do
      sensor_data = {
        battery: 85,
        temperature: 22.5,
        motion: true
      }

      summary = test_instance.format_sensor_summary(sensor_data)
      expect(summary).to eq('Battery: 85%, Temp: 22.5°C, Motion: detected')
    end

    it 'handles missing sensor data gracefully' do
      sensor_data = {
        battery: 45,
        temperature: nil,
        motion: false
      }

      summary = test_instance.format_sensor_summary(sensor_data)
      expect(summary).to eq('Battery: 45%, Motion: none')
    end

    it 'returns nil for empty sensor data' do
      summary = test_instance.format_sensor_summary({})
      expect(summary).to be_nil
    end
  end

  describe '#with_retry' do
    it 'succeeds on first attempt' do
      attempt_count = 0

      result = test_instance.with_retry('test_operation') do
        attempt_count += 1
        'success'
      end

      expect(result).to eq('success')
      expect(attempt_count).to eq(1)
    end

    it 'retries with simple backoff for art installation' do
      attempt_count = 0

      allow(test_instance).to receive(:sleep).with(0.5).once

      result = test_instance.with_retry('test_operation', max_retries: 2) do
        attempt_count += 1
        raise 'Temporary error' if attempt_count < 2

        'success'
      end

      expect(result).to eq('success')
      expect(attempt_count).to eq(2)
    end

    it 'raises error after max attempts' do
      expect do
        test_instance.with_retry('test_operation', max_retries: 2) do
          raise 'Persistent error'
        end
      end.to raise_error('Persistent error')
    end

    it 'prints warning after failed attempts' do
      expect do
        test_instance.with_retry('test_operation', max_retries: 2) do
          raise StandardError, 'Test error with long message that should be truncated'
        end
      end.to raise_error('Test error with long message that should be truncated')
    end
  end

  describe '#enrich_context_with_sensors' do
    let(:mock_client) { instance_double(HomeAssistantClient) }
    let(:context) { { include_sensors: true } }

    before do
      allow(HomeAssistantClient).to receive(:new).and_return(mock_client)
    end

    it 'enriches context with sensor data' do
      allow(mock_client).to receive_messages(battery_level: 85, temperature: 22.5, motion_detected?: false)

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
      allow(mock_client).to receive_messages(temperature: 22.5, motion_detected?: true)

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

  describe '#attempt_connection_recovery' do
    it 'only attempts recovery in development environment' do
      allow(ENV).to receive(:[]).with('RACK_ENV').and_return('production')

      result = test_instance.attempt_connection_recovery
      expect(result).to be false
    end

    it 'attempts docker restart in development' do
      allow(ENV).to receive(:[]).with('RACK_ENV').and_return('development')
      allow(test_instance).to receive(:system).with('docker-compose restart homeassistant 2>/dev/null').and_return(true)
      allow(test_instance).to receive(:sleep).with(1)

      result = test_instance.attempt_connection_recovery
      expect(result).to be true
    end

    it 'handles system command failures gracefully' do
      allow(ENV).to receive(:[]).with('RACK_ENV').and_return('development')
      allow(test_instance).to receive(:system).and_raise(StandardError, 'Command failed')

      result = test_instance.attempt_connection_recovery
      expect(result).to be false
    end
  end

  describe '#add_message_to_conversation' do
    let(:conversation) { { messages: [] } }
    let(:message_data) do
      {
        role: 'user',
        content: 'Hello',
        cost: 0.001,
        prompt_tokens: 10,
        completion_tokens: 5
      }
    end

    it 'adds message to conversation with timestamp' do
      result = test_instance.add_message_to_conversation(conversation, message_data)

      expect(conversation[:messages].length).to eq(1)
      expect(result[:timestamp]).to be_present
      expect(conversation[:total_cost]).to eq(0.001)
      expect(conversation[:total_tokens]).to eq(15)
    end

    it 'handles conversation without existing messages' do
      empty_conversation = {}

      test_instance.add_message_to_conversation(empty_conversation, message_data)

      expect(empty_conversation[:messages].length).to eq(1)
    end

    it 'accumulates costs and tokens' do
      test_instance.add_message_to_conversation(conversation, message_data)
      test_instance.add_message_to_conversation(conversation, { cost: 0.002, prompt_tokens: 20, completion_tokens: 10 })

      expect(conversation[:total_cost]).to eq(0.003)
      expect(conversation[:total_tokens]).to eq(45)
    end
  end

  describe '#update_conversation_totals' do
    it 'calculates totals from all messages' do
      conversation = {
        messages: [
          { cost: 0.001, prompt_tokens: 10, completion_tokens: 5 },
          { cost: 0.002, prompt_tokens: 15, completion_tokens: 8 },
          { prompt_tokens: 5 } # Message without cost/completion_tokens
        ]
      }

      result = test_instance.update_conversation_totals(conversation)

      expect(result[:total_cost]).to eq(0.003)
      expect(result[:total_tokens]).to eq(43) # 10+5+15+8+5+0
    end

    it 'handles empty messages array' do
      conversation = { messages: [] }

      result = test_instance.update_conversation_totals(conversation)

      expect(result[:total_cost]).to eq(0.0)
      expect(result[:total_tokens]).to eq(0)
    end
  end
end
