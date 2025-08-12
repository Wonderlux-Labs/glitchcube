#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../../config/environment'

def test_buddy_json_response
  puts 'Testing BUDDY with new JSON format...'
  puts '=' * 50

  # Create BUDDY persona
  buddy = GlitchCube::Personas::Buddy.new({})

  # Get system prompt
  system_prompt = buddy.generate_system_prompt

  puts 'System Prompt Preview:'
  puts "#{system_prompt[0..500]}..."
  puts '=' * 50

  # Test message
  test_message = 'Hey there! Can you help me find the bathroom?'

  puts "\nTest Message: #{test_message}"
  puts '=' * 50

  # Call LLM with new format expectations
  response = Services::LLMService.complete(
    system_prompt: system_prompt,
    user_message: test_message,
    model: 'openai/gpt-4o-mini',
    temperature: 0.8,
    max_tokens: 500
  )

  puts "\nRaw Response Content:"
  puts response.content
  puts '=' * 50

  puts "\nParsed JSON:"
  if response.parsed_content
    pp response.parsed_content
  else
    puts 'Failed to parse as JSON'
  end
  puts '=' * 50

  puts "\nExtracted Fields:"
  puts "speak_to_user: #{response.response_text}"
  puts "continue_conversation: #{response.continue_conversation?}"
  puts "inner_thoughts: #{response.inner_thoughts}"
  puts "proactive_behaviors: #{response.proactive_behaviors}"
  puts '=' * 50

  # Test with tool calls
  puts "\nTesting with tool-enabled context..."

  tool_response = Services::LLMService.complete(
    system_prompt: system_prompt,
    user_message: 'Play some music for me!',
    model: 'openai/gpt-4o-mini',
    temperature: 0.8,
    max_tokens: 500,
    tools: %w[display_control set_state]
  )

  puts "\nTool Response Content:"
  puts tool_response.content

  if tool_response.tool_calls?
    puts "\nTool Calls Detected:"
    pp tool_response.tool_calls
  end

  puts "\n✅ Test completed successfully!"
rescue StandardError => e
  puts "\n❌ Error during testing:"
  puts e.message
  puts e.backtrace.first(5)
end

test_buddy_json_response
