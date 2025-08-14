# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/tools/hass_mcp_tool'

# TODO: Investigate VCR recording for STDIO subprocess interactions
# MCP uses mcp-proxy via STDIO which VCR doesn't capture
# These tests run live against the real MCP proxy
RSpec.describe Tools::HassMcpTool, :vcr do
  before(:context) do
    unless ENV['RUN_MCP'] == 'true'
      skip 'MCP tests require local mcp-proxy - skipping in CI'
    end
  end
  describe '.call' do
    context 'GetLiveContext' do
      it 'retrieves current device states' do
        VCR.use_cassette('mcp_tool/get_live_context') do
          result = described_class.call(
            mcp_function: 'GetLiveContext',
            mcp_params: {}
          )

          expect(result).to be_a(String)
          expect(result).to include('✅')

          # Should contain device information
          expect(result).to match(/light|sensor|media_player/i)
        end
      end
    end

    context 'light control' do
      it 'turns on a light' do
        VCR.use_cassette('mcp_tool/turn_on_light') do
          result = described_class.call(
            mcp_function: 'HassTurnOn',
            mcp_params: { name: 'Cube Light' }
          )

          expect(result).to include('✅')
          expect(result).to include('successful')
        end
      end

      it 'turns off a light' do
        VCR.use_cassette('mcp_tool/turn_off_light') do
          result = described_class.call(
            mcp_function: 'HassTurnOff',
            mcp_params: { name: 'Cube Light' }
          )

          expect(result).to include('✅')
        end
      end

      it 'sets light properties' do
        VCR.use_cassette('mcp_tool/set_light_properties') do
          result = described_class.call(
            mcp_function: 'HassLightSet',
            mcp_params: {
              name: 'Cube Light',
              brightness: 60,
              color: 'green'
            }
          )

          expect(result).to include('✅')
        end
      end

      it 'handles multiple lights' do
        VCR.use_cassette('mcp_tool/control_multiple_lights') do
          # Turn on Cart Light
          result1 = described_class.call(
            mcp_function: 'HassTurnOn',
            mcp_params: { name: 'Cart Light' }
          )
          expect(result1).to include('✅')

          # Set Cube Light
          result2 = described_class.call(
            mcp_function: 'HassLightSet',
            mcp_params: {
              name: 'Cube Light',
              brightness: 100,
              color: 'red'
            }
          )
          expect(result2).to include('✅')
        end
      end
    end

    context 'media control' do
      it 'sets volume on media player' do
        VCR.use_cassette('mcp_tool/set_volume') do
          result = described_class.call(
            mcp_function: 'HassSetVolume',
            mcp_params: {
              name: 'Square Voice Media Player',
              volume_level: 75
            }
          )

          expect(result).to include('✅').or include('successful')
        end
      end

      it 'pauses media playback' do
        VCR.use_cassette('mcp_tool/pause_media') do
          result = described_class.call(
            mcp_function: 'HassMediaPause',
            mcp_params: { name: 'Square Voice Media Player' }
          )

          expect(result).to be_a(String)
          # Result depends on current state but should not error
        end
      end
    end

    context 'error handling' do
      it 'handles invalid MCP function gracefully' do
        VCR.use_cassette('mcp_tool/invalid_function') do
          result = described_class.call(
            mcp_function: 'NonExistentFunction',
            mcp_params: {}
          )

          expect(result).to include('❌')
          expect(result).to include('Error')
        end
      end

      it 'handles invalid entity gracefully' do
        VCR.use_cassette('mcp_tool/invalid_entity') do
          result = described_class.call(
            mcp_function: 'HassTurnOn',
            mcp_params: { name: 'Fake Device That Does Not Exist' }
          )

          expect(result).to include('❌')
        end
      end

      it 'handles missing required function parameter' do
        expect do
          described_class.call(mcp_params: { name: 'Cube Light' })
        end.to raise_error(Tools::BaseTool::ValidationError, /Missing required parameters: mcp_function/)
      end

      it 'handles JSON string parameters' do
        VCR.use_cassette('mcp_tool/json_string_params') do
          result = described_class.call(
            mcp_function: 'HassLightSet',
            mcp_params: '{"name": "Cube Light", "brightness": 80}'
          )

          expect(result).to include('✅')
        end
      end
    end

    context 'complex scenarios' do
      it 'executes a sequence of commands for scene setup' do
        VCR.use_cassette('mcp_tool/scene_setup') do
          # Get initial state
          initial_state = described_class.call(
            mcp_function: 'GetLiveContext',
            mcp_params: {}
          )
          expect(initial_state).to include('✅')

          # Turn on all lights
          described_class.call(
            mcp_function: 'HassTurnOn',
            mcp_params: { name: 'Cube Light' }
          )

          described_class.call(
            mcp_function: 'HassTurnOn',
            mcp_params: { name: 'Cart Light' }
          )

          # Set mood lighting
          described_class.call(
            mcp_function: 'HassLightSet',
            mcp_params: {
              name: 'Cube Light',
              brightness: 30,
              color: 'purple'
            }
          )

          # Verify final state
          final_state = described_class.call(
            mcp_function: 'GetLiveContext',
            mcp_params: {}
          )
          expect(final_state).to include('✅')
        end
      end
    end
  end

  describe '.list_available_functions' do
    it 'returns list of available MCP functions' do
      VCR.use_cassette('mcp_tool/list_functions') do
        functions = described_class.list_available_functions

        expect(functions).to be_an(Array)
        expect(functions).not_to be_empty

        # Check structure
        functions.each do |func|
          expect(func).to include(:name, :description)
        end

        # Check for expected functions
        function_names = functions.map { |f| f[:name] }
        expect(function_names).to include('HassTurnOn')
        expect(function_names).to include('GetLiveContext')
      end
    end
  end

  describe '.get_function_schema' do
    it 'returns schema for a specific function' do
      VCR.use_cassette('mcp_tool/get_schema') do
        schema = described_class.get_function_schema('HassLightSet')

        expect(schema).to be_a(Hash)
        expect(schema).to include(:name, :description, :parameters, :required)
        expect(schema[:name]).to eq('HassLightSet')
      end
    end
  end

  describe 'tool metadata' do
    it 'has correct name' do
      expect(described_class.name).to eq('hass_mcp')
    end

    it 'has description' do
      expect(described_class.description).to include('Home Assistant')
      expect(described_class.description).to include('MCP')
    end

    it 'defines parameters' do
      params = described_class.parameters
      expect(params).to include(:mcp_function, :mcp_params)
      expect(params[:mcp_function][:required]).to be true
    end

    it 'provides examples' do
      examples = described_class.examples
      expect(examples).to be_an(Array)
      expect(examples).not_to be_empty

      # Check first example
      first_example = examples.first
      expect(first_example).to include(:description, :params)
      expect(first_example[:params]).to include(:mcp_function, :mcp_params)
    end

    it 'has category' do
      expect(described_class.category).to eq('home_automation')
    end

    it 'has tool prompt' do
      prompt = described_class.tool_prompt
      expect(prompt).to include('HassTurnOn')
      expect(prompt).to include('HassLightSet')
      expect(prompt).to include('GetLiveContext')
    end
  end
end
