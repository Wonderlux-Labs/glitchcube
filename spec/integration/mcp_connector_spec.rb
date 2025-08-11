# frozen_string_literal: true

require 'spec_helper'
require 'services/mcp_connector_service'
require 'tools/hass_mcp_tool'

# TODO: Investigate VCR recording for STDIO subprocess interactions
# MCP uses mcp-proxy via STDIO which VCR doesn't capture
# These tests run live against the real MCP proxy
RSpec.describe Services::McpConnectorService, :vcr do
  before(:context) do
    if ENV['CI'] == 'true'
      skip 'MCP tests require local mcp-proxy - skipping in CI'
    end
  end
  let(:service) { described_class.instance }

  before do
    # Reset singleton state
    service.disconnect!
  end

  after do
    service.disconnect!
  end

  describe '#connect!' do
    it 'establishes connection to MCP server' do
      VCR.use_cassette('mcp/connection_success') do
        expect(service.connect!).to be true
        expect(service).to be_connected
      end
    end

    it 'fetches available tools on connection' do
      VCR.use_cassette('mcp/list_tools') do
        service.connect!
        tools = service.list_tools

        expect(tools).to be_an(Array)
        expect(tools).not_to be_empty

        # Check for expected Home Assistant MCP tools
        tool_names = tools.map { |t| t['name'] }
        expect(tool_names).to include('HassTurnOn')
        expect(tool_names).to include('HassTurnOff')
        expect(tool_names).to include('GetLiveContext')
        expect(tool_names).to include('HassLightSet')
      end
    end

    it 'handles connection failures gracefully' do
      # Temporarily set invalid URL
      allow(ENV).to receive(:[]).with('MCP_HA_URL').and_return('http://invalid:9999')

      VCR.use_cassette('mcp/connection_failure') do
        expect { service.connect! }.to raise_error(Services::McpConnectorService::ConnectionError)
        expect(service).not_to be_connected
      end
    end
  end

  describe '#execute_tool' do
    before do
      VCR.use_cassette('mcp/connection_for_execute') do
        service.connect!
      end
    end

    context 'GetLiveContext' do
      it 'retrieves current state of all devices' do
        VCR.use_cassette('mcp/get_live_context') do
          result = service.execute_tool('GetLiveContext', {})

          expect(result).to be_a(Hash).or be_a(String)

          # If it's a formatted string response, it should contain device info
          if result.is_a?(String)
            expect(result).to include('light').or include('sensor').or include('media_player')
          end
        end
      end
    end

    context 'HassTurnOn' do
      it 'turns on a light successfully' do
        VCR.use_cassette('mcp/turn_on_light') do
          result = service.execute_tool('HassTurnOn', { name: 'Cube Light' })

          expect(result).to include(:success)
          expect(result[:success]).to be true
          expect(result[:message]).to include('successful')
        end
      end

      it 'handles invalid entity gracefully' do
        VCR.use_cassette('mcp/turn_on_invalid_entity') do
          expect do
            service.execute_tool('HassTurnOn', { name: 'NonExistent Light' })
          end.to raise_error(Services::McpConnectorService::ExecutionError)
        end
      end
    end

    context 'HassTurnOff' do
      it 'turns off a light successfully' do
        VCR.use_cassette('mcp/turn_off_light') do
          result = service.execute_tool('HassTurnOff', { name: 'Cube Light' })

          expect(result).to include(:success)
          expect(result[:success]).to be true
        end
      end
    end

    context 'HassLightSet' do
      it 'sets light brightness and color' do
        VCR.use_cassette('mcp/set_light_properties') do
          result = service.execute_tool('HassLightSet', {
                                          name: 'Cube Light',
                                          brightness: 75,
                                          color: 'blue'
                                        })

          expect(result).to include(:success)
          expect(result[:success]).to be true
        end
      end
    end

    context 'HassSetVolume' do
      it 'sets media player volume' do
        VCR.use_cassette('mcp/set_volume') do
          result = service.execute_tool('HassSetVolume', {
                                          name: 'Square Voice Media Player',
                                          volume_level: 50
                                        })

          expect(result).to include(:success)
        end
      end
    end
  end

  describe '#execute_tools' do
    it 'executes multiple tools in batch' do
      VCR.use_cassette('mcp/batch_execution') do
        service.connect!

        tool_calls = [
          { name: 'GetLiveContext', parameters: {} },
          { name: 'HassTurnOn', parameters: { name: 'Cube Light' } },
          { name: 'HassLightSet', parameters: { name: 'Cube Light', brightness: 50 } }
        ]

        results = service.execute_tools(tool_calls)

        expect(results).to be_an(Array)
        expect(results.size).to eq(3)

        results.each do |result|
          expect(result).to include(:name, :result)
        end
      end
    end
  end

  describe '#get_tool_schema' do
    before do
      VCR.use_cassette('mcp/connection_for_schema') do
        service.connect!
      end
    end

    it 'retrieves schema for a specific tool' do
      VCR.use_cassette('mcp/get_tool_schema') do
        schema = service.get_tool_schema('HassLightSet')

        expect(schema).to be_a(Hash)
        expect(schema).to include(:name, :description, :parameters, :required)
        expect(schema[:name]).to eq('HassLightSet')
        expect(schema[:parameters]).to include('name')
      end
    end

    it 'returns nil for non-existent tool' do
      schema = service.get_tool_schema('NonExistentTool')
      expect(schema).to be_nil
    end
  end

  describe '#reconnect!' do
    it 'disconnects and reconnects successfully' do
      VCR.use_cassette('mcp/reconnect') do
        service.connect!
        expect(service).to be_connected

        service.reconnect!
        expect(service).to be_connected

        # Should still be able to execute tools
        result = service.execute_tool('GetLiveContext', {})
        expect(result).not_to be_nil
      end
    end
  end
end
