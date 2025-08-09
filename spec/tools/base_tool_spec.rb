# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/tools/base_tool'

RSpec.describe BaseTool do
  describe 'class methods' do
    describe '.name' do
      it 'returns snake_case version of class name', :vcr do
        expect(described_class.name).to eq('base_tool')
      end
    end

    describe '.description' do
      it 'raises NotImplementedError', :vcr do
        expect { described_class.description }.to raise_error(NotImplementedError, 'Tool must implement .description method')
      end
    end

    describe '.call' do
      it 'raises NotImplementedError', :vcr do
        expect { described_class.call }.to raise_error(NotImplementedError, 'Tool must implement .call method')
      end
    end

    describe '.parameters' do
      it 'returns empty hash by default', :vcr do
        expect(described_class.parameters).to eq({})
      end
    end

    describe '.required_parameters' do
      it 'returns empty array by default', :vcr do
        expect(described_class.required_parameters).to eq([])
      end
    end

    describe '.examples' do
      it 'returns empty array by default', :vcr do
        expect(described_class.examples).to eq([])
      end
    end

    describe '.category' do
      it 'returns general by default', :vcr do
        expect(described_class.category).to eq('general')
      end
    end
  end

  describe 'protected methods' do
    # Create a test class that exposes protected methods
    let(:test_tool_class) do
      Class.new(BaseTool) do
        def self.name
          'test_tool'
        end

        def self.description
          'Test tool for specs'
        end

        def self.call(**_args)
          'test result'
        end

        # Expose protected methods for testing
        class << self
          public :validate_required_params, :parse_json_params, :format_response, :ha_client
        end
      end
    end

    describe '.validate_required_params' do
      it 'raises ValidationError for missing required parameters', :vcr do
        params = { 'action' => 'test' }
        required = %w[action target]

        expect do
          test_tool_class.validate_required_params(params, required)
        end.to raise_error(BaseTool::ValidationError, 'Missing required parameters: target')
      end

      it 'raises ValidationError for multiple missing parameters', :vcr do
        params = { 'action' => 'test' }
        required = %w[action target value]

        expect do
          test_tool_class.validate_required_params(params, required)
        end.to raise_error(BaseTool::ValidationError, 'Missing required parameters: target, value')
      end

      it 'does not raise error when all required parameters are present', :vcr do
        params = { 'action' => 'test', 'target' => 'light' }
        required = %w[action target]

        expect do
          test_tool_class.validate_required_params(params, required)
        end.not_to raise_error
      end

      it 'handles nil values as missing', :vcr do
        params = { 'action' => nil }
        required = ['action']

        expect do
          test_tool_class.validate_required_params(params, required)
        end.to raise_error(BaseTool::ValidationError, 'Missing required parameters: action')
      end
    end

    describe '.parse_json_params' do
      it 'returns hash unchanged if already a hash', :vcr do
        params = { 'key' => 'value' }
        expect(test_tool_class.parse_json_params(params)).to eq(params)
      end

      it 'returns empty hash for nil', :vcr do
        expect(test_tool_class.parse_json_params(nil)).to eq({})
      end

      it 'returns empty hash for empty string', :vcr do
        expect(test_tool_class.parse_json_params('')).to eq({})
      end

      it 'parses valid JSON string', :vcr do
        json_string = '{"action":"test","value":123}'
        expected = { 'action' => 'test', 'value' => 123 }
        expect(test_tool_class.parse_json_params(json_string)).to eq(expected)
      end

      it 'parses JSON with nested objects', :vcr do
        json_string = '{"action":"test","params":{"brightness":50,"color":[255,0,0]}}'
        result = test_tool_class.parse_json_params(json_string)
        expect(result['params']['brightness']).to eq(50)
        expect(result['params']['color']).to eq([255, 0, 0])
      end

      it 'raises ValidationError for invalid JSON', :vcr do
        invalid_json = '{"invalid": json'
        expect do
          test_tool_class.parse_json_params(invalid_json)
        end.to raise_error(BaseTool::ValidationError, /Invalid JSON parameters/)
      end

      it 'raises ValidationError for non-JSON string', :vcr do
        invalid_string = 'not json at all'
        expect do
          test_tool_class.parse_json_params(invalid_string)
        end.to raise_error(BaseTool::ValidationError, /Invalid JSON parameters/)
      end
    end

    describe '.format_response' do
      it 'formats success response with checkmark', :vcr do
        result = test_tool_class.format_response(true, 'Operation successful')
        expect(result).to eq('✅ Operation successful')
      end

      it 'formats failure response with X', :vcr do
        result = test_tool_class.format_response(false, 'Operation failed')
        expect(result).to eq('❌ Operation failed')
      end

      it 'includes data when provided', :vcr do
        data = { 'result' => 'test' }
        result = test_tool_class.format_response(true, 'Success', data)
        expect(result).to eq("✅ Success\nData: {\"result\" => \"test\"}")
      end

      it 'handles nil data gracefully', :vcr do
        result = test_tool_class.format_response(true, 'Success', nil)
        expect(result).to eq('✅ Success')
      end
    end

    describe '.ha_client' do
      context 'when mock is enabled' do
        before do
          # Add mock_enabled to the config if it doesn't exist
          original_config = GlitchCube.config.home_assistant
          allow(GlitchCube.config).to receive(:home_assistant).and_return(
            OpenStruct.new(
              url: original_config.url,
              token: original_config.token,
              mock_enabled: true
            )
          )
        end

        it 'returns MockHomeAssistantClient instance', :vcr do
          client = test_tool_class.ha_client
          expect(client).to be_a(MockHomeAssistantClient)
        end
      end

      context 'when Home Assistant is not configured' do
        before do
          allow(GlitchCube.config).to receive(:home_assistant).and_return(
            OpenStruct.new(
              url: nil,
              token: nil,
              mock_enabled: false
            )
          )
        end

        it 'raises ToolError with helpful message', :vcr do
          expect do
            test_tool_class.ha_client
          end.to raise_error(BaseTool::ToolError, /Home Assistant not configured/)
        end
      end

      context 'when Home Assistant is configured' do
        before do
          GlitchCube.config.home_assistant
          allow(GlitchCube.config).to receive(:home_assistant).and_return(
            OpenStruct.new(
              url: 'http://localhost:8123',
              token: 'test-token',
              mock_enabled: false
            )
          )
          allow(HomeAssistantClient).to receive(:new).and_return(double('ha_client'))
        end

        it 'returns HomeAssistantClient instance', :vcr do
          client = test_tool_class.ha_client
          expect(client).not_to be_nil
        end
      end
    end
  end

  describe 'MockHomeAssistantClient' do
    let(:mock_client) { MockHomeAssistantClient.new }

    describe '#call_service' do
      it 'returns true for any service call', :vcr do
        result = mock_client.call_service('light', 'turn_on', { entity_id: 'light.test' })
        expect(result).to be true
      end

      it 'prints mock message to stdout', :vcr do
        expect do
          mock_client.call_service('script', 'test', { param: 'value' })
        end.to output(/Mock HA: script.test/).to_stdout
      end
    end

    describe '#state' do
      it 'returns mock state hash', :vcr do
        state = mock_client.state('sensor.test')
        expect(state).to be_a(Hash)
        expect(state['state']).to eq('mock_state')
        expect(state['attributes']['friendly_name']).to eq('Mock sensor.test')
      end
    end

    describe '#speak' do
      it 'returns true for TTS', :vcr do
        result = mock_client.speak('Test message')
        expect(result).to be true
      end

      it 'prints TTS message to stdout', :vcr do
        expect do
          mock_client.speak('Hello', entity_id: 'media_player.test')
        end.to output(/Mock TTS: 'Hello' on media_player.test/).to_stdout
      end
    end
  end
end
