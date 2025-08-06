#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'open_router'
require 'dotenv'
require 'json'
require 'faraday'

Dotenv.load

# Let's intercept at the Faraday level to see what's really happening
class FaradayLogger < Faraday::Middleware
  def call(env)
    puts "\n=== REQUEST ==="
    puts "URL: #{env.url}"
    puts "Headers: #{env.request_headers.select { |k, _| k.downcase.include?('content') || k.downcase.include?('auth') }.inspect}"
    puts "Body (first 500): #{env.body.to_s[0..500]}"
    
    @app.call(env).on_complete do |response_env|
      puts "\n=== RESPONSE ==="
      puts "Status: #{response_env.status}"
      puts "Headers: #{response_env.response_headers.select { |k, _| k.downcase.include?('content') }.inspect}"
      puts "Body class: #{response_env.body.class}"
      puts "Body (first 500): #{response_env.body.to_s[0..500]}"
    end
  end
end

# Patch the client to use our logger
module OpenRouter
  class Client
    def connection
      @connection ||= Faraday.new(url: uri_base || "https://openrouter.ai/api/v1") do |f|
        f.use FaradayLogger
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
      end
    end
  end
end

client = OpenRouter::Client.new(access_token: ENV['OPENROUTER_API_KEY'])

schema = {
  type: "json_schema",
  json_schema: {
    name: "response",
    strict: true,
    schema: {
      type: "object",
      properties: {
        response: { type: "string" },
        continue_conversation: { type: "boolean" }
      },
      required: ["response", "continue_conversation"],
      additionalProperties: false
    }
  }
}

begin
  response = client.complete(
    [{ role: 'user', content: 'Hello! How are you today?' }],
    model: ENV['DEFAULT_AI_MODEL'] || 'openrouter/auto',
    extras: {
      response_format: schema,
      temperature: 0.7,
      max_tokens: 150
    }
  )
  
  puts "\n=== FINAL ==="
  puts "Success! Response: #{response.dig('choices', 0, 'message', 'content')}"
rescue => e
  puts "\n=== ERROR ==="
  puts "Error: #{e.class} - #{e.message}"
  puts e.backtrace.first(5)
end