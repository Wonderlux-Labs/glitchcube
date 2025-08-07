#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'app'

puts "🔍 Testing LLM Service Directly..."

# Simple test message
messages = [
  { role: 'system', content: 'You are a helpful assistant.' },
  { role: 'user', content: 'Hello, tell me about art' }
]

# Test without structured output first
puts "\n=== TEST 1: Simple completion (no structured output) ==="
response1 = Services::LLMService.complete_with_messages(
  messages: messages,
  model: 'google/gemini-2.5-flash',
  max_tokens: 500,
  temperature: 0.8
)

puts "Response class: #{response1.class}"
puts "Content: #{response1.content}"
puts "Response text: #{response1.response_text}"
puts "Content length: #{response1.content&.length}"

# Test with structured output
puts "\n=== TEST 2: Structured output (JSON schema) ==="
schema = {
  type: "json_schema",
  json_schema: {
    name: "response",
    strict: true,
    schema: {
      type: "object",
      properties: {
        response: { type: "string", description: "The response text" },
        continue_conversation: { type: "boolean", description: "Whether to continue the conversation" }
      },
      required: ["response", "continue_conversation"],
      additionalProperties: false
    }
  }
}

response2 = Services::LLMService.complete_with_messages(
  messages: messages,
  model: 'google/gemini-2.5-flash',
  max_tokens: 500,
  temperature: 0.8,
  response_format: schema
)

puts "Response class: #{response2.class}"
puts "Content: #{response2.content}"
puts "Parsed content: #{response2.parsed_content.inspect}"
puts "Response text: #{response2.response_text}"
puts "Content length: #{response2.content&.length}"

puts "\n✅ LLM Direct Test completed."