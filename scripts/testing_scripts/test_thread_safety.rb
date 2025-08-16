#!/usr/bin/env ruby
# frozen_string_literal: true

# Thread safety test for the FlowManager async implementation

puts "\n🔒 Thread Safety Test for FlowManager\n"
puts '=' * 60

# Test basic configuration and initialization
begin
  if defined?(GlitchCube)
    puts '✅ GlitchCube module is loaded'

    # Test async configuration
    if GlitchCube.config.async_tools_enabled?
      puts "✅ Async tools enabled with #{GlitchCube.config.async_max_threads} max threads"
    else
      puts '⚠️ Async tools disabled, skipping thread safety tests'
      exit 0
    end

    # Test FlowManager initialization with thread safety
    puts "\n🧵 Testing FlowManager Thread Safety..."

    flow_manager = Services::Conversation::FlowManager.new
    puts '✅ FlowManager created with thread pool'

    # Test health check
    health = flow_manager.health_check
    puts "✅ Thread pool health: #{health}"
    puts "   - Pool size: #{health[:thread_pool_size]}"
    puts "   - Queue size: #{health[:thread_pool_queue_size]}"
    puts "   - Remaining capacity: #{health[:thread_pool_remaining_capacity]}"
    puts "   - Healthy: #{health[:healthy]}"

    # Test concurrent access simulation
    puts "\n🚀 Testing Concurrent Access Simulation..."

    # Simulate multiple concurrent sessions
    threads = []
    results = Concurrent::Array.new
    start_time = Time.now

    5.times do |i|
      threads << Thread.new do
        session_id = "test_session_#{i}"

        begin
          # Simulate conversation processing (without actual LLM calls)
          context = {
            session_id: session_id,
            persona: 'buddy',
            voice_interaction: true,
            test_mode: true
          }

          # This would normally call the full conversation flow
          # For testing, we just check thread safety of session management
          session = flow_manager.instance_variable_get(:@state_manager)
                                .create_or_get_session(session_id, context)

          results << {
            thread_id: Thread.current.object_id,
            session_id: session_id,
            success: true,
            timestamp: Time.now
          }
        rescue StandardError => e
          results << {
            thread_id: Thread.current.object_id,
            session_id: session_id,
            success: false,
            error: e.message,
            timestamp: Time.now
          }
        end
      end
    end

    # Wait for all threads to complete
    threads.each(&:join)
    duration = Time.now - start_time

    # Analyze results
    successful = results.count { |r| r[:success] }
    failed = results.count { |r| !r[:success] }

    puts '📊 Concurrent Test Results:'
    puts "   - Total operations: #{results.size}"
    puts "   - Successful: #{successful}"
    puts "   - Failed: #{failed}"
    puts "   - Duration: #{(duration * 1000).round}ms"
    puts "   - Average per operation: #{(duration * 1000 / results.size).round}ms"

    if failed.positive?
      puts "\n❌ Failures detected:"
      results.reject { |r| r[:success] }.each do |failure|
        puts "   - Thread #{failure[:thread_id]}: #{failure[:error]}"
      end
    else
      puts "\n✅ All concurrent operations succeeded!"
    end

    # Test shutdown
    puts "\n🛑 Testing Graceful Shutdown..."
    flow_manager.shutdown(timeout: 5)

    final_health = flow_manager.health_check
    puts '✅ Shutdown completed. Final state:'
    puts "   - Pool shutdown: #{final_health[:thread_pool_shutdown]}"
    puts "   - Active sessions: #{final_health[:active_sessions]}"

    puts "\n🎉 Thread Safety Test Complete!"

  else
    puts '❌ GlitchCube module not loaded'
    puts '   This script should be run from bin/console'
    puts '   Usage: bin/console'
    puts "          load 'scripts/testing_scripts/test_thread_safety.rb'"
  end
rescue StandardError => e
  puts "❌ Error during testing: #{e.message}"
  puts "   #{e.backtrace.first(3).join("\n   ")}"
  exit 1
end
