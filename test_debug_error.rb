#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'dotenv'
Dotenv.load

require_relative 'config/initializers/config'
require_relative 'lib/services/llm_service'
require_relative 'lib/services/llm_response'
require_relative 'lib/schemas/conversation_response_schema'

puts "Debugging Error"
puts "=" * 50

schema = GlitchCube::Schemas::ConversationResponseSchema.simple_response
formatted_schema = GlitchCube::Schemas::ConversationResponseSchema.to_openrouter_format(schema)

begin
  response = Services::LLMService.complete(
    system_prompt: "You are a helpful assistant. Always respond with structured JSON.",
    user_message: "Hello! How are you today?",
    model: ENV['DEFAULT_AI_MODEL'] || 'openrouter/auto',
    temperature: 0.7,
    max_tokens: 150,
    response_format: formatted_schema
  )
  
  puts "Success!"
  puts "Response: #{response.response_text}"
  
rescue => e
  puts "Error class: #{e.class}"
  puts "Error message: #{e.message}"
  puts "Error inspect: #{e.inspect}"
  puts "\nBacktrace:"
  puts e.backtrace.first(10)
end