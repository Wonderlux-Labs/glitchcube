#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'open_router'
require 'dotenv'
require 'json'

Dotenv.load

# Monkey patch to see what's happening
module OpenRouter
  class Client
    alias original_post post

    def post(path:, parameters:)
      puts "Sending request to: #{path}"
      puts "Parameters: #{parameters.inspect[0..500]}"

      result = original_post(path: path, parameters: parameters)

      puts "Response class: #{result.class}"
      puts "Response (first 500 chars): #{result.inspect[0..500]}"

      result
    end
  end
end

client = OpenRouter::Client.new(access_token: ENV.fetch('OPENROUTER_API_KEY', nil))

# Test with a model that might not support structured outputs
schema = {
  type: 'json_schema',
  json_schema: {
    name: 'greeting',
    strict: true,
    schema: {
      type: 'object',
      properties: {
        greeting: { type: 'string' },
        language: { type: 'string' }
      },
      required: %w[greeting language],
      additionalProperties: false
    }
  }
}

begin
  response = client.complete(
    [{ role: 'user', content: 'Say hello in French' }],
    model: ENV['DEFAULT_AI_MODEL'] || 'google/gemini-2.5-flash',
    extras: {
      response_format: schema,
      temperature: 0.5
    }
  )

  puts "\nFinal response: #{response.class}"
rescue StandardError => e
  puts "\nError: #{e.class} - #{e.message}"
  puts e.backtrace.first(5)
end
