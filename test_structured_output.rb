#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for structured output functionality
require 'bundler/setup'
require 'dotenv'
Dotenv.load

require_relative 'config/initializers/config'
require_relative 'lib/services/llm_service'
require_relative 'lib/services/llm_response'
require_relative 'lib/schemas/conversation_response_schema'

puts "Testing Structured Output Support"
puts "=" * 50

# Test 1: Simple structured response
puts "\nTest 1: Simple Structured Response"
puts "-" * 30

schema = GlitchCube::Schemas::ConversationResponseSchema.simple_response
formatted_schema = GlitchCube::Schemas::ConversationResponseSchema.to_openrouter_format(schema)

puts "Schema:"
puts JSON.pretty_generate(formatted_schema)

begin
  response = Services::LLMService.complete(
    system_prompt: "You are a helpful assistant. Always respond with structured JSON.",
    user_message: "Hello! How are you today?",
    model: ENV['DEFAULT_AI_MODEL'] || 'openrouter/auto',
    temperature: 0.7,
    max_tokens: 150,
    response_format: formatted_schema
  )
  
  puts "\nResponse object class: #{response.class}"
  puts "Response text: #{response.response_text}"
  puts "Continue conversation? #{response.continue_conversation?}"
  puts "Parsed content: #{response.parsed_content.inspect}"
  
rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(5)
end

# Test 2: Tool calling
puts "\n\nTest 2: Tool Calling"
puts "-" * 30

tools = [
  {
    type: "function",
    function: {
      name: "get_weather",
      description: "Get the current weather in a location",
      parameters: {
        type: "object",
        properties: {
          location: {
            type: "string",
            description: "The city and state, e.g. San Francisco, CA"
          },
          unit: {
            type: "string",
            enum: ["celsius", "fahrenheit"]
          }
        },
        required: ["location"]
      }
    }
  }
]

begin
  response = Services::LLMService.complete(
    system_prompt: "You are a helpful assistant. Use tools when appropriate.",
    user_message: "What's the weather in San Francisco?",
    model: 'google/gemini-2.5-flash',  # Our default model that supports tools
    temperature: 0.7,
    max_tokens: 150,
    tools: tools,
    tool_choice: "auto"
  )
  
  puts "Has tool calls? #{response.has_tool_calls?}"
  if response.has_tool_calls?
    puts "Tool calls: #{response.tool_calls.inspect}"
    puts "Function arguments: #{response.parse_function_arguments}"
  end
  puts "Response text: #{response.response_text}"
  
rescue => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(5)
end

# Test 3: Testing conversation continuation logic
puts "\n\nTest 3: Conversation Continuation"
puts "-" * 30

test_messages = [
  "Tell me about art",
  "Goodbye!",
  "What do you think about creativity?",
  "That's all for now, thanks!"
]

test_messages.each do |msg|
  puts "\nMessage: \"#{msg}\""
  
  begin
    response = Services::LLMService.complete(
      system_prompt: "You are GlitchCube, an autonomous art installation. Respond naturally and indicate if the conversation should continue.",
      user_message: msg,
      model: ENV['DEFAULT_AI_MODEL'] || 'openrouter/auto',
      temperature: 0.8,
      max_tokens: 100,
      response_format: GlitchCube::Schemas::ConversationResponseSchema.to_openrouter_format(
        GlitchCube::Schemas::ConversationResponseSchema.simple_response
      )
    )
    
    puts "  Response: #{response.response_text[0..100]}..."
    puts "  Continue? #{response.continue_conversation?}"
    
  rescue => e
    puts "  Error: #{e.message}"
  end
end

puts "\n" + "=" * 50
puts "Testing complete!"