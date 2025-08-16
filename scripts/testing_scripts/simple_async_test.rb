#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple async conversation test that only tests configuration

puts "\n🧪 Simple Async Configuration Test\n"
puts '=' * 50

# Test if we can at least check the basic setup
begin
  # Just check if the basic configuration constants are there
  if defined?(GlitchCube)
    puts '✅ GlitchCube module is loaded'
    puts "✅ Config system available: #{GlitchCube.config.class}"

    # Test async configuration
    if GlitchCube.config.respond_to?(:async_tools_enabled?)
      puts '✅ Async tools config available'
      puts "   - Enabled: #{GlitchCube.config.async_tools_enabled?}"
      puts "   - Immediate timeout: #{GlitchCube.config.async_immediate_timeout}s"
      puts "   - Background timeout: #{GlitchCube.config.async_background_timeout}s"
      puts "   - Follow-up delay: #{GlitchCube.config.async_follow_up_delay}s"
      puts "   - Max threads: #{GlitchCube.config.async_max_threads}"
      puts "   - Fallback to sync: #{GlitchCube.config.async_fallback_to_sync?}"
    else
      puts '❌ Async tools configuration not available'
    end

    # Test if services exist
    if defined?(Services::Conversation::FlowManager)
      puts '✅ FlowManager class is available'

      # Try to create a FlowManager instance (this tests basic initialization)
      flow_manager = Services::Conversation::FlowManager.new
      puts '✅ FlowManager instance created successfully'

      # Test if async flow methods exist
      if flow_manager.respond_to?(:should_use_async_flow?, true)
        puts '✅ Async flow methods are available'
      else
        puts '❌ Async flow methods not found'
      end
    else
      puts '❌ FlowManager class not available'
    end

  else
    puts '❌ GlitchCube module not loaded'
    puts '   This script should be run from bin/console'
    puts '   Usage: bin/console'
    puts "          load 'scripts/testing_scripts/simple_async_test.rb'"
  end
rescue StandardError => e
  puts "❌ Error during testing: #{e.message}"
  puts "   #{e.backtrace.first}"
end

puts "\n📋 Quick Manual Test:"
puts '   1. Check configuration is working above'
puts '   2. For full testing, run: bin/console'
puts "   3. Then: load 'scripts/testing_scripts/test_async_conversation.rb'"
puts '   4. Or run: bin/rspec spec/services/conversation/async_flow_spec.rb'
