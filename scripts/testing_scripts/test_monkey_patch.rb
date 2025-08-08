#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'dotenv'
Dotenv.load

# Monkey patch to see what the hell is happening
require 'open_router'

module OpenRouter
  class Client
    alias original_complete complete

    def complete(messages, model: 'openrouter/auto', providers: [], transforms: [], extras: {}, stream: nil)
      parameters = { messages: messages }
      if model.is_a?(String)
        parameters[:model] = model
      elsif model.is_a?(Array)
        parameters[:models] = model
        parameters[:route] = 'fallback'
      end
      parameters[:provider] = { provider: { order: providers } } if providers.any?
      parameters[:transforms] = transforms if transforms.any?
      parameters[:stream] = stream if stream
      parameters.merge!(extras)

      response = post(path: '/chat/completions', parameters: parameters)

      puts "RESPONSE CLASS: #{response.class}"
      puts "RESPONSE: #{response.inspect[0..1000]}"

      response.tap do |r|
        if r.is_a?(String)
          puts "GOT A STRING RESPONSE: #{r}"
          raise ServerError, "Got string response: #{r}"
        end

        raise ServerError, r.dig('error', 'message') if r.presence&.dig('error', 'message').present?
        raise ServerError, 'Empty response from OpenRouter. Might be worth retrying once or twice.' if stream.blank? && r.blank?
        return r.with_indifferent_access if r.is_a?(Hash)
      end
    end
  end
end

require_relative 'config/initializers/config'
require_relative 'lib/services/llm_service'
require_relative 'lib/schemas/conversation_response_schema'

schema = GlitchCube::Schemas::ConversationResponseSchema.simple_response
formatted_schema = GlitchCube::Schemas::ConversationResponseSchema.to_openrouter_format(schema)

begin
  Services::LLMService.complete(
    system_prompt: 'You are a helpful assistant.',
    user_message: 'Hello!',
    model: 'google/gemini-2.5-flash',
    temperature: 0.7,
    max_tokens: 150,
    response_format: formatted_schema
  )

  puts "\nSUCCESS!"
rescue StandardError => e
  puts "\nERROR: #{e.message}"
  puts e.backtrace.first(3)
end
