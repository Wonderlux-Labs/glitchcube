#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to demonstrate the self-healing error handler
# WARNING: Only run in development environment!

require_relative 'config/initializers/config'
require_relative 'lib/services/error_handling_llm'
require_relative 'lib/error_handler_integration'
require 'redis'

puts '🧬 Self-Healing Error Handler Test'
puts '⚠️  WARNING: This is experimental and can modify code!'
puts
puts 'Configuration:'
puts "  - Self-healing enabled: #{GlitchCube.config.enable_self_healing}"
puts "  - Min confidence: #{GlitchCube.config.self_healing_min_confidence}"
puts "  - Error threshold: #{GlitchCube.config.self_healing_error_threshold}"
puts

if GlitchCube.config.production?
  puts '❌ ABORTED: Will not run in production environment'
  exit 1
end

unless GlitchCube.config.enable_self_healing
  puts '❌ Self-healing is disabled. Set ENABLE_SELF_HEALING=true to test.'
  exit 1
end

# Simulate a service with an error
class TestService
  include ErrorHandlerIntegration

  def problematic_method
    puts '🚨 Simulating a problematic method that fails...'

    with_error_healing do
      # This will fail and trigger the error handler
      raise StandardError, 'Connection refused to external service'
    end
  rescue StandardError => e
    puts "  Error caught: #{e.message}"
    false
  end
end

# Test the error handling system
puts '🧪 Testing error handler...'
service = TestService.new

# First few errors should just be tracked
3.times do |i|
  puts "\n--- Attempt #{i + 1} ---"
  service.problematic_method
end

puts "\n✅ Test completed!"
puts '📊 Check Redis for error tracking:'
puts "   redis-cli keys 'glitchcube:error_count:*'"
puts '📋 Check logs for self-healing attempts'
puts
puts '🔄 To test rollback functionality:'
puts "   ruby -r './lib/services/error_handling_llm' -e 'Services::ErrorHandlingLLM.new.rollback_last_fix'"
