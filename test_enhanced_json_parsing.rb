#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for enhanced JSON parsing and action extraction

# Add the lib directory to the load path
$LOAD_PATH.unshift(File.expand_path('lib', __dir__))

# Load required dependencies
require 'json'
require 'active_support/core_ext/hash/indifferent_access'
require 'ostruct'

# Load our classes
require 'services/llm/llm_response'
require 'services/conversation/action_extractor'
require 'services/logging/simple_logger'

def test_json_parsing
  puts '🧪 Testing Enhanced JSON Parsing & Action Extraction'
  puts '=' * 60

  # Test cases for various JSON response formats
  test_cases = [
    {
      name: 'Clean JSON',
      content: '{"response": "I\'ll help you with that!", "actions": ["Make the cube lights a dusky purple at 50% brightness", "Queue up some Grateful Dead, maybe Cosmic Charlie"], "continue_conversation": true}'
    },
    {
      name: 'JSON with code blocks',
      content: '```json
{
  "response": "Perfect! Let me set that up for you.",
  "actions": ["Set all LED strips to warm amber glow at 25% intensity", "Play some chill lo-fi beats"],
  "continue_conversation": false
}
```'
    },
    {
      name: 'Mixed content with JSON',
      content: 'Here is my response to your request:

{
  "response": "Absolutely! I can do that for you.",
  "actions": ["Turn the art car lights to a soft blue-green gradient", "Start playing some ambient forest sounds"],
  "inner_thoughts": "This should create a nice vibe"
}'
    },
    {
      name: 'Malformed JSON (should fallback)',
      content: 'JSON response:
```json
{
  "response": "I\'ll get right on that!",
  "actions": ["Play some classic rock, maybe Led Zeppelin IV",]
  "continue_conversation": true,
}
```'
    }
  ]

  test_cases.each_with_index do |test_case, i|
    puts "\n🧪 Test Case #{i + 1}: #{test_case[:name]}"
    puts '-' * 40

    # Create a mock LLM response
    response = Services::Llm::LLMResponse.new({
                                                content: test_case[:content],
                                                model: 'google/gemini-2.5-flash',
                                                usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 }
                                              })

    puts "📥 Raw content: #{test_case[:content][0..100]}#{'...' if test_case[:content].length > 100}"
    puts "🔧 Parsed content: #{response.parsed_content.inspect}"
    puts "📝 Response text: #{response.response_text.inspect}"

    # Test action extraction
    action_extractor = Services::Conversation::ActionExtractor.new
    action_result = action_extractor.extract_and_execute_actions(response.parsed_content || response.response_text, 'test_session')

    puts "🎬 Actions extracted: #{action_result[:extracted_actions].inspect}"
    puts "✅ Success: #{action_result[:success]}"
  end
end

def test_action_extractor_directly
  puts "\n\n🧪 Testing ActionExtractor Directly"
  puts '=' * 60

  # Test direct hash input
  test_hash = {
    'response' => 'Great! Setting that up now.',
    'actions' => [
      'Make the cube and cart lights a dusky purple at 50% brightness',
      'Queue up some Grateful Dead, maybe Cosmic Charlie',
      'Display "Welcome to the Playa" on the LED matrix'
    ],
    'continue_conversation' => true
  }

  action_extractor = Services::Conversation::ActionExtractor.new
  result = action_extractor.extract_and_execute_actions(test_hash, 'test_session_direct')

  puts "📥 Input hash: #{test_hash.inspect}"
  puts "🎬 Actions extracted: #{result[:extracted_actions].inspect}"
  puts "✅ Success: #{result[:success]}"
  puts "📋 Summary: #{result[:execution_summary]}"
end

# Run the tests
begin
  test_json_parsing
  test_action_extractor_directly
  puts "\n🎉 All tests completed!"
rescue StandardError => e
  puts "\n❌ Test failed: #{e.message}"
  puts e.backtrace.first(5)
end
