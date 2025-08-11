#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'mcp_client'
require 'json'

puts 'Testing MCP Connection to Home Assistant...'
puts '=' * 50

# Try different connection methods
def test_stdio_proxy
  puts "\n1. Testing STDIO proxy connection (like Claude uses)..."

  begin
    client = MCPClient.create_client(
      mcp_server_configs: [
        MCPClient.stdio_config(
          command: 'uvx',
          args: ['mcp-proxy'],
          env: {
            'SSE_URL' => 'http://glitch.local:8123/mcp_server/sse',
            'API_ACCESS_TOKEN' => 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJmODZmMzA0NjYwMjg0YTI0YWNkMzM5NzI0YjBiMjhmZSIsImlhdCI6MTc1NDQxNzE0MiwiZXhwIjoyMDY5Nzc3MTQyfQ.QrzutqtPKbnXpFbiALjC8ppCfuaNnUsep7CWQMBK1kw'
          }
        )
      ]
    )

    puts '✅ Client created successfully'

    # List available tools
    puts "\nListing available tools..."
    tools = client.list_tools
    puts "Found #{tools.size} tools:"
    tools.first(5).each do |tool|
      puts "  - #{tool['name']}: #{tool['description']&.first(60)}..."
    end

    # Test GetLiveContext
    puts "\nTesting GetLiveContext..."
    result = client.call_tool('GetLiveContext', {})
    puts '✅ GetLiveContext successful!'
    puts "Result: #{result.to_s.first(200)}..."

    # Test light control
    puts "\nTesting light control..."
    result = client.call_tool('HassTurnOn', { 'name' => 'Cube Light' })
    puts '✅ Light control successful!'

    true
  rescue StandardError => e
    puts "❌ Error: #{e.message}"
    puts e.backtrace.first(5)
    false
  end
end

def test_direct_sse
  puts "\n2. Testing direct SSE connection..."

  begin
    client = MCPClient.create_client(
      mcp_server_configs: [
        MCPClient.sse_config(
          base_url: 'http://glitch.local:8123/mcp_server/sse',
          headers: {
            'Authorization' => 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJmODZmMzA0NjYwMjg0YTI0YWNkMzM5NzI0YjBiMjhmZSIsImlhdCI6MTc1NDQxNzE0MiwiZXhwIjoyMDY5Nzc3MTQyfQ.QrzutqtPKbnXpFbiALjC8ppCfuaNnUsep7CWQMBK1kw'
          },
          read_timeout: 30,
          retries: 3
        )
      ]
    )

    puts '✅ SSE Client created'

    # Try to connect
    client.connect if client.respond_to?(:connect)

    # List tools
    tools = client.list_tools
    puts "Found #{tools.size} tools via SSE"

    true
  rescue StandardError => e
    puts "❌ SSE Error: #{e.message}"
    false
  end
end

# Run tests
success = false

# Try STDIO proxy first (like Claude uses)
if test_stdio_proxy
  puts "\n✅ STDIO proxy connection works! Use this method."
  success = true
end

# Try direct SSE as fallback
if !success && test_direct_sse
  puts "\n✅ Direct SSE connection works!"
  success = true
end

puts "\n#{'=' * 50}"
if success
  puts '✅ MCP CONNECTION SUCCESSFUL!'
  puts 'Update McpConnectorService to use the working method.'
else
  puts '❌ Could not establish MCP connection.'
  puts 'Check that Home Assistant is running and MCP server is configured.'
end
