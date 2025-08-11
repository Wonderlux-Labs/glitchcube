#!/usr/bin/env ruby
# frozen_string_literal: true

# Direct test of self-healing functionality

# Set the environment variable before requiring anything
ENV['SELF_HEALING'] = 'DRY_RUN'
ENV['RACK_ENV'] = 'development'

require 'bundler/setup'
require_relative 'config/environment'
require_relative 'config/initializers/config'
require_relative 'lib/services/system/error_handling_llm'

puts '🧬 Self-Healing Error Handler Test'
puts '⚠️  WARNING: This is experimental and can modify code!'
puts

puts 'Configuration:'
puts "  - Self-healing mode: #{GlitchCube.config.self_healing_mode}"
puts "  - Self-healing enabled: #{GlitchCube.config.self_healing_enabled?}"
puts "  - Min confidence: #{GlitchCube.config.self_healing_min_confidence}"
puts "  - Error threshold: #{GlitchCube.config.self_healing_error_threshold}"
puts

# Test the error handling directly
puts '🧪 Testing Services::ErrorHandlingLLM directly...'

handler = Services::ErrorHandlingLLM.new
error = StandardError.new('Test connection refused error')
context = {
  service: 'TestService',
  method: 'test_method',
  file: __FILE__,
  line: __LINE__,
  timestamp: Time.now.iso8601,
  environment: 'development'
}

puts "\n--- Testing Error Handler ---"
puts "Error: #{error.message}"
puts "Context: #{context}"

result = handler.handle_error(error, context)

puts "\nResult: #{result.inspect}"
puts "\n✅ Test completed!"
