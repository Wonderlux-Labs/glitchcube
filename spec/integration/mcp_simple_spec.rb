# frozen_string_literal: true

require 'spec_helper'
require 'mcp_client'

# TODO: Investigate VCR recording for STDIO subprocess interactions
# MCP uses mcp-proxy via STDIO which VCR doesn't capture
# These tests run live against the real MCP proxy
RSpec.describe 'MCP Integration', :vcr do
  before(:context) do
    if ENV['CI'] == 'true'
      skip 'MCP tests require local mcp-proxy - skipping in CI'
    end
  end
  let(:client) do
    base_url = GlitchCube.config.mcp_url || "#{GlitchCube.config.home_assistant.url}/mcp_server/sse"
    token = GlitchCube.config.home_assistant.token

    MCPClient.create_client(
      mcp_server_configs: [
        MCPClient.stdio_config(
          command: 'uvx mcp-proxy',
          env: {
            'SSE_URL' => base_url,
            'API_ACCESS_TOKEN' => token
          }
        )
      ]
    )
  end

  describe 'basic functionality' do
    it 'lists available tools' do
      VCR.use_cassette('mcp_simple/list_tools') do
        tools = client.list_tools

        expect(tools).to be_an(Array)
        expect(tools).not_to be_empty

        tool_names = tools.map(&:name)
        expect(tool_names).to include('HassTurnOn')
        expect(tool_names).to include('GetLiveContext')
      end
    end

    it 'gets live context' do
      VCR.use_cassette('mcp_simple/get_live_context') do
        result = client.call_tool('GetLiveContext', {})

        expect(result).to be_a(Hash)
        expect(result['content']).to be_an(Array)

        # Extract text content
        text_content = result['content'].find { |c| c['type'] == 'text' }
        expect(text_content).not_to be_nil

        # Parse the JSON response
        parsed = JSON.parse(text_content['text'])
        expect(parsed['success']).to be true
        expect(parsed['result']).to include('Live Context')
      end
    end

    it 'turns on a light' do
      VCR.use_cassette('mcp_simple/turn_on_light') do
        result = client.call_tool('HassTurnOn', { 'name' => 'Cube Light' })

        expect(result).to be_a(Hash)

        # Extract and parse response
        text_content = result['content'].find { |c| c['type'] == 'text' }
        parsed = JSON.parse(text_content['text'])

        expect(parsed['response_type']).to eq('action_done')
        expect(parsed['data']['success']).to be_an(Array)
      end
    end

    it 'sets light properties' do
      VCR.use_cassette('mcp_simple/set_light') do
        result = client.call_tool('HassLightSet', {
                                    'name' => 'Cube Light',
                                    'brightness' => 75,
                                    'color' => 'blue'
                                  })

        expect(result).to be_a(Hash)

        # Extract and parse response
        text_content = result['content'].find { |c| c['type'] == 'text' }
        parsed = JSON.parse(text_content['text'])

        expect(parsed['response_type']).to eq('action_done')
      end
    end
  end
end
