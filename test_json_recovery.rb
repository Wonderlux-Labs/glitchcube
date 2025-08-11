#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for JSON recovery feature

require_relative 'config/environment'

# Test 1: Valid JSON (should work normally)
puts 'Test 1: Valid JSON'
valid_json = '{"response": "Hello world", "continue_conversation": false}'
response1 = Services::LLMResponse.new(
  content: valid_json,
  expects_json: true
)
puts "Parsed content: #{response1.parsed_content.inspect}"
puts "Response text: #{response1.response_text.inspect}"
puts '---'

# Test 2: Malformed JSON (should trigger recovery)
puts "\nTest 2: Malformed JSON with recovery"
malformed_json = '{"response": "Hello world, "continue_conversation": false}'  # Missing closing quote
response2 = Services::LLMResponse.new(
  content: malformed_json,
  expects_json: true
)
puts "Parsed content: #{response2.parsed_content.inspect}"
puts "Response text: #{response2.response_text.inspect}"
puts '---'

# Test 3: Plain text when not expecting JSON (should return as-is)
puts "\nTest 3: Plain text (not expecting JSON)"
plain_text = 'Hello, this is just plain text'
response3 = Services::LLMResponse.new(
  content: plain_text,
  expects_json: false
)
puts "Parsed content: #{response3.parsed_content.inspect}"
puts "Response text: #{response3.response_text.inspect}"
puts '---'

# Test 4: JSON-like text when not expecting JSON (should not parse)
puts "\nTest 4: JSON-like text but not expecting JSON"
json_like = '{"response": "This looks like JSON but should be treated as text"}'
response4 = Services::LLMResponse.new(
  content: json_like,
  expects_json: false
)
puts "Parsed content: #{response4.parsed_content.inspect}"
puts "Response text: #{response4.response_text.inspect}"
