# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/proactive_conversation_service'

RSpec.describe Services::ProactiveConversationService do
  let(:mock_client) { instance_double(HomeAssistantClient) }
  let(:mock_handler) { double('ConversationHandlerService') }  # Use regular double instead of instance_double
  let(:service) { described_class.new }  # Create service AFTER mocks are set up

  before do
    # Mock the class instantiation to return our mock objects
    allow(HomeAssistantClient).to receive(:new).and_return(mock_client)
    allow(Services::ConversationHandlerService).to receive(:new).and_return(mock_handler)
    
    # Also ensure mocks are properly set up
    allow(mock_client).to receive_messages(
      state: { 'state' => 'off' },  # default state
      awtrix_notify: { success: true }
    )
    # Remove the conflicting mock - let individual tests set up their own expectations
    allow(Services::LoggerService).to receive(:log_interaction)
  end

  describe '#check_single_trigger' do
    let(:motion_config) do
      {
        entity: 'binary_sensor.motion',
        condition: ->(state) { state == 'on' },
        cooldown: 300,
        message: 'Motion detected!'
      }
    end

    context 'when trigger condition is met' do
      it 'returns triggered result' do
        allow(mock_client).to receive(:state).with('binary_sensor.motion').and_return(
          { 'state' => 'on' }
        )

        result = service.check_single_trigger(:motion_detected, motion_config)

        expect(result[:triggered]).to be true
        expect(result[:trigger]).to eq(:motion_detected)
        expect(result[:value]).to eq('on')
      end
    end

    context 'when trigger is in cooldown' do
      it 'returns not triggered with cooldown reason' do
        # Set last trigger time
        service.instance_variable_get(:@last_trigger_times)[:motion_detected] = Time.now - 60

        result = service.check_single_trigger(:motion_detected, motion_config)

        expect(result[:triggered]).to be false
        expect(result[:reason]).to eq('cooldown')
      end
    end

    context 'when condition is not met' do
      it 'returns not triggered' do
        allow(mock_client).to receive(:state).with('binary_sensor.motion').and_return(
          { 'state' => 'off' }
        )

        result = service.check_single_trigger(:motion_detected, motion_config)

        expect(result[:triggered]).to be false
      end
    end

    context 'when entity check fails' do
      it 'handles error gracefully' do
        allow(mock_client).to receive(:state).and_raise('Entity not found')

        expect { service.check_single_trigger(:motion_detected, motion_config) }.not_to raise_error

        result = service.check_single_trigger(:motion_detected, motion_config)
        expect(result[:triggered]).to be false
      end
    end
  end

  describe '#initiate_proactive_conversation' do
    let(:trigger_result) do
      {
        trigger: :battery_low,
        triggered: true,
        entity: 'sensor.battery_level',
        value: '15',
        message: ->(v) { "Battery at #{v}%!" }
      }
    end

    it 'sends conversation to Home Assistant' do
      # Use stubs to set up mock behavior
      allow(mock_handler).to receive(:send_conversation_to_ha).and_return({ status: 'sent' })
      allow(Services::LoggerService).to receive(:log_interaction)
      allow(mock_client).to receive(:awtrix_notify).and_return({ success: true })

      result = service.initiate_proactive_conversation(trigger_result)
      
      expect(result).to include(status: 'sent')
      
      # Verify calls were made with correct arguments
      expect(mock_handler).to have_received(:send_conversation_to_ha).with(
        'Battery at 15%!',
        hash_including(
          trigger: :battery_low,
          proactive: true
        )
      )
      
      expect(Services::LoggerService).to have_received(:log_interaction).with(
        hash_including(
          user_message: '[PROACTIVE: battery_low]',
          ai_response: 'Battery at 15%!',
          mood: 'proactive',
          context: { trigger: :battery_low }
        )
      )
      
      expect(mock_client).to have_received(:awtrix_notify).with(
        '💬 Battery at 15%!...',
        hash_including(color: [100, 200, 255])
      )
    end

    it 'handles errors gracefully' do
      allow(mock_handler).to receive(:send_conversation_to_ha).and_raise('Network error')

      expect { service.initiate_proactive_conversation(trigger_result) }.not_to raise_error

      result = service.initiate_proactive_conversation(trigger_result)
      expect(result).to be_nil
    end
  end

  describe '#check_triggers' do
    it 'checks all triggers in parallel' do
      service.register_triggers

      # Mock all entity states
      allow(mock_client).to receive(:state).with('binary_sensor.motion').and_return({ 'state' => 'off' })
      allow(mock_client).to receive(:state).with('sensor.battery_level').and_return({ 'state' => '85' })
      allow(mock_client).to receive(:state).with('sensor.temperature').and_return({ 'state' => '22' })
      allow(mock_client).to receive(:state).with('sensor.last_interaction').and_return({ 'state' => Time.now.iso8601 })

      results = service.check_triggers

      expect(results).to be_empty # No triggers activated
    end

    it 'processes triggered conversations' do
      allow(mock_client).to receive(:state).with('binary_sensor.motion').and_return({ 'state' => 'on' })
      allow(mock_client).to receive(:state).with('sensor.battery_level').and_return({ 'state' => '85' })
      allow(mock_client).to receive(:state).with('sensor.temperature').and_return({ 'state' => '22' })
      allow(mock_client).to receive(:state).with('sensor.last_interaction').and_return({ 'state' => Time.now.iso8601 })

      expect(service).to receive(:initiate_proactive_conversation).once

      results = service.check_triggers
      expect(results).not_to be_empty
    end
  end

  describe 'message generators' do
    it 'generates contextual motion messages' do
      generator = service.generate_motion_message
      message = generator.call(nil)

      expect(message).to be_a(String)
      expect(message).to include('!')
    end

    it 'generates battery messages with value' do
      generator = service.generate_battery_message
      message = generator.call('15')

      expect(message).to include('15%')
    end

    it 'generates temperature messages based on value' do
      hot_generator = service.generate_temperature_message
      hot_message = hot_generator.call('35')

      expect(hot_message).to include('35')
      expect(hot_message).to match(/warm|hot|toasty/i)

      cold_message = hot_generator.call('5')
      expect(cold_message).to include('5')
      # Allow for all possible cold temperature message variants
      expect(cold_message).to match(/cold|chilly|brrr|bundled up/i)
    end
  end

  describe '#start_monitoring' do
    it 'starts a monitoring thread' do
      expect(Thread).to receive(:new).and_yield
      expect(service).to receive(:check_triggers).and_return([])
      # Expect two sleep calls: one normal, one in rescue block after error
      expect(service).to receive(:sleep).with(60).and_raise(StandardError, 'Test stop')
      expect(service).to receive(:sleep).with(60).and_raise(StandardError, 'Test stop again')

      expect { service.start_monitoring }.to raise_error('Test stop again')
    end
  end

  describe '#stop_monitoring' do
    it 'kills the monitoring thread' do
      mock_thread = instance_double(Thread)
      service.instance_variable_set(:@monitoring_thread, mock_thread)

      expect(mock_thread).to receive(:kill)

      service.stop_monitoring
      expect(service.instance_variable_get(:@monitoring_thread)).to be_nil
    end
  end
end
