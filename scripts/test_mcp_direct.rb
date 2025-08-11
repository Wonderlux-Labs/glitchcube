#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'mcp_client'
require 'json'

puts 'Testing direct MCP SSE connection...'

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

puts 'Client created, listing tools...'
tools = client.list_tools
puts "Found #{tools.size} tools"

puts "\nFirst 5 tools:"
tools.first(5).each do |tool|
  puts "- #{tool.name}"
end

puts "\nTesting GetLiveContext..."
result = client.call_tool('GetLiveContext', {})
puts "Result type: #{result.class}"
puts "Result (truncated): #{result.to_s[0..200]}..."

puts "\n✅ Success!"
