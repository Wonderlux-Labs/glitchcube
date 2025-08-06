#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'open_router'
require 'dotenv'
require 'json'

Dotenv.load

puts "Testing OpenRouter gem directly"
puts "=" * 50

client = OpenRouter::Client.new(access_token: ENV['OPENROUTER_API_KEY'])

# Test 1: Basic call
puts "\nTest 1: Basic message"
begin
  response = client.complete(
    [{ role: 'user', content: 'Say hello in 5 words or less' }],
    model: 'openrouter/auto'
  )
  
  puts "Response class: #{response.class}"
  puts "Response keys: #{response.keys}" if response.is_a?(Hash)
  puts "Content: #{response.dig('choices', 0, 'message', 'content')}" if response.is_a?(Hash)
rescue => e
  puts "Error: #{e.class} - #{e.message}"
  puts e.backtrace.first(3)
end

# Test 2: With extras (structured output)
puts "\nTest 2: With structured output"
begin
  schema = {
    type: "json_schema",
    json_schema: {
      name: "greeting",
      strict: true,
      schema: {
        type: "object",
        properties: {
          greeting: { type: "string" },
          language: { type: "string" }
        },
        required: ["greeting", "language"],
        additionalProperties: false
      }
    }
  }
  
  response = client.complete(
    [{ role: 'user', content: 'Say hello in French' }],
    model: 'openai/gpt-4o-mini',  # Use a model that supports structured outputs
    extras: {
      response_format: schema,
      temperature: 0.5
    }
  )
  
  puts "Response class: #{response.class}"
  puts "Content: #{response.dig('choices', 0, 'message', 'content')}" if response.is_a?(Hash)
rescue => e
  puts "Error: #{e.class} - #{e.message}"
  puts e.backtrace.first(3)
end

# Test 3: With tools
puts "\nTest 3: With tools"
begin
  tools = [
    {
      type: "function",
      function: {
        name: "get_weather",
        description: "Get weather for a location",
        parameters: {
          type: "object",
          properties: {
            location: { type: "string" }
          },
          required: ["location"]
        }
      }
    }
  ]
  
  response = client.complete(
    [{ role: 'user', content: "What's the weather in Paris?" }],
    model: 'openai/gpt-4o-mini',
    extras: {
      tools: tools,
      tool_choice: "auto"
    }
  )
  
  puts "Response class: #{response.class}"
  if response.is_a?(Hash)
    content = response.dig('choices', 0, 'message', 'content')
    tool_calls = response.dig('choices', 0, 'message', 'tool_calls')
    puts "Content: #{content}"
    puts "Tool calls: #{tool_calls.inspect}" if tool_calls
  end
rescue => e
  puts "Error: #{e.class} - #{e.message}"
  puts e.backtrace.first(3)
end

puts "\n" + "=" * 50
puts "Testing complete!"