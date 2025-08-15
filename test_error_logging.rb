#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick test to verify error logging works

require_relative 'config/environment'
require 'faraday'

# Create a mock error that simulates the 400 error we were getting
error_response = {
  status: 400,
  body: '{"error": {"message": "anthropic-claude-sonnet-4 is not a valid model ID", "code": 400}}'
}

faraday_error = Faraday::BadRequestError.new('the server responded with status 400')
# Mock the response method
def faraday_error.response
  {
    status: 400,
    body: '{"error": {"message": "anthropic-claude-sonnet-4 is not a valid model ID", "code": 400}}'
  }
end

puts 'Testing error logging...'
puts '=' * 50

begin
  Services::Llm::Components::ErrorHandler.handle_error(faraday_error)
rescue StandardError => e
  puts '✅ Error was handled correctly!'
  puts "Error type: #{e.class}"
  puts "Error message: #{e.message}"
  puts ''
  puts 'Check the logs above - you should see:'
  puts "1. 'RAW ERROR DUMP' debug message with full error details"
  puts "2. 'LLM API ERROR RESPONSE BODY' error message"
  puts "3. The actual API error: 'anthropic-claude-sonnet-4 is not a valid model ID'"
end
