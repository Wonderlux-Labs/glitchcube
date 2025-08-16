# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::Conversation::FlowManager, type: :service do
  let(:flow_manager) { described_class.new }

  describe 'thread safety' do
    before do
      # Skip if async tools are disabled
      skip 'Async tools disabled' unless GlitchCube.config.async_tools_enabled?
    end

    describe 'initialization' do
      it 'creates thread-safe data structures' do
        expect(flow_manager.instance_variable_get(:@active_tool_threads)).to be_a(Concurrent::Hash)
        expect(flow_manager.instance_variable_get(:@thread_pool)).to be_a(Concurrent::FixedThreadPool)
      end

      it 'respects configured thread pool size' do
        thread_pool = flow_manager.instance_variable_get(:@thread_pool)
        expect(thread_pool.pool_size).to eq(GlitchCube.config.async_max_threads)
      end
    end

    describe 'health_check' do
      it 'returns thread pool status' do
        health = flow_manager.health_check

        expect(health).to include(
          :thread_pool_size,
          :thread_pool_queue_size,
          :thread_pool_remaining_capacity,
          :active_sessions,
          :thread_pool_shutdown,
          :healthy
        )

        expect(health[:healthy]).to be true
        expect(health[:thread_pool_shutdown]).to be false
      end
    end

    describe 'concurrent session management' do
      it 'handles multiple concurrent sessions safely' do
        results = Concurrent::Array.new
        threads = []

        # Create multiple threads accessing the flow manager concurrently
        10.times do |i|
          threads << Thread.new do
            session_id = "test_session_#{i}"
            context = {
              session_id: session_id,
              persona: 'buddy',
              voice_interaction: true
            }

            begin
              # Test thread-safe session creation
              state_manager = flow_manager.instance_variable_get(:@state_manager)
              session = state_manager.create_or_get_session(session_id, context)

              results << {
                thread_id: Thread.current.object_id,
                session_id: session_id,
                success: true
              }
            rescue StandardError => e
              results << {
                thread_id: Thread.current.object_id,
                session_id: session_id,
                success: false,
                error: e.message
              }
            end
          end
        end

        # Wait for all threads
        threads.each(&:join)

        # Verify all operations succeeded
        failures = results.reject { |r| r[:success] }
        expect(failures).to be_empty, "Concurrent failures: #{failures.inspect}"
        expect(results.size).to eq(10)
      end
    end

    describe 'thread pool management' do
      it 'prevents thread pool exhaustion' do
        thread_pool = flow_manager.instance_variable_get(:@thread_pool)
        initial_capacity = thread_pool.remaining_capacity

        # Try to submit more tasks than the pool can handle
        futures = []
        (GlitchCube.config.async_max_threads + 2).times do
          future = Concurrent::Future.execute(executor: thread_pool) do
            sleep(0.1) # Small delay to occupy threads
            'completed'
          end
          futures << future
        end

        # Wait for completion
        futures.each { |f| f.wait(1.0) }

        # Pool should still be healthy
        expect(thread_pool.shutdown?).to be false
        expect(thread_pool.remaining_capacity).to eq(initial_capacity)
      end
    end

    describe 'shutdown' do
      it 'gracefully shuts down the thread pool' do
        health_before = flow_manager.health_check
        expect(health_before[:healthy]).to be true

        flow_manager.shutdown(timeout: 2)

        health_after = flow_manager.health_check
        expect(health_after[:thread_pool_shutdown]).to be true
        expect(health_after[:active_sessions]).to eq(0)
      end

      it 'clears active thread references on shutdown' do
        active_threads = flow_manager.instance_variable_get(:@active_tool_threads)

        # Simulate some active threads
        active_threads['session1'] = 'mock_future'
        active_threads['session2'] = 'mock_future'

        expect(active_threads.size).to eq(2)

        flow_manager.shutdown(timeout: 1)

        expect(active_threads.size).to eq(0)
      end
    end

    describe 'background thread error handling' do
      it 'handles errors without crashing the system' do
        persona_instance = instance_double('Persona', name: 'buddy')

        expect do
          flow_manager.send(
            :handle_background_thread_error,
            StandardError.new('test error'),
            'test_execution_id',
            'test_session_id',
            persona_instance
          )
        end.not_to raise_error
      end
    end
  end

  describe 'timeout handling' do
    before do
      skip 'Async tools disabled' unless GlitchCube.config.async_tools_enabled?
    end

    it 'uses Concurrent::Promises instead of Timeout.timeout' do
      # Verify that the dangerous Timeout.timeout is not used
      flow_manager_code = File.read(
        File.join(__dir__, '../../../lib/services/conversation/flow_manager.rb')
      )

      # Should not contain the dangerous pattern
      expect(flow_manager_code).not_to include('Timeout.timeout')

      # Should use the safe alternative
      expect(flow_manager_code).to include('Concurrent::Promises')
    end
  end
end
