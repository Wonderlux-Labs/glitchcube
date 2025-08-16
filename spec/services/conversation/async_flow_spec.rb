# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Async Conversation Flow', :vcr do
  include_context 'with full conversation setup'
  include_context 'with async conversation setup'

  let(:flow_manager) { Services::Conversation::FlowManager.new }

  before do
    # Ensure we have the necessary shared contexts available
    include_context 'with_lights_available'
    include_context 'with_media_players_available'

    # Mock external LLM calls to focus on async flow testing
    mock_llm_response_with_tools(
      response: "I'll turn on the lights and start some music for you!",
      actions: sample_async_actions
    )
  end

  describe 'Async Tool Execution Flow' do
    context 'when async tools are enabled' do
      it 'returns immediate response for tool-heavy requests' do
        mock_ha_tts_calls
        mock_successful_tool_execution

        response = flow_manager.process_conversation(
          message: 'turn on the lights and play some music',
          context: async_test_context,
          persona: 'buddy'
        )

        expect_immediate_response(response)
        expect(response['data']['speech_text']).to include('On it')
      end

      it 'generates persona-appropriate acknowledgments' do
        mock_ha_tts_calls
        mock_successful_tool_execution

        # Test with different personas
        %w[buddy jax lomi zorp].each do |persona|
          response = flow_manager.process_conversation(
            message: 'turn on the lights',
            context: async_test_context.merge(session_id: "test_#{persona}"),
            persona: persona
          )

          expect_immediate_response(response)
          expect(response['data']['speech_text']).to be_a(String)
          expect(response['data']['speech_text']).not_to be_empty
        end
      end

      it 'executes tools in background thread' do
        mock_ha_tts_calls

        # Count tool execution calls
        execution_count = 0
        allow_any_instance_of(Services::Conversation::ToolExecutionEngine)
          .to receive(:execute_action) do |*_args|
            execution_count += 1
            { success: true, result: "Tool #{execution_count} executed" }
          end

        response = flow_manager.process_conversation(
          message: async_trigger_message,
          context: async_test_context,
          persona: 'buddy'
        )

        expect_async_flow_triggered(response)

        # Wait for background execution
        wait_for_async_completion(max_wait: 6.0)

        # Verify tools were executed
        expect(execution_count).to be > 0
        expect_thread_cleanup
      end

      it 'sends follow-up TTS after tool completion' do
        mock_successful_tool_execution

        # Track TTS calls
        tts_calls = []
        allow_any_instance_of(Services::Core::HomeAssistantClient)
          .to receive(:speak_with_retry) do |_instance, message, **options|
            tts_calls << { message: message, options: options }
            true
          end

        allow_any_instance_of(Services::Core::HomeAssistantClient)
          .to receive(:speak_as_persona) do |_instance, message, persona, **options|
            tts_calls << { message: message, persona: persona, options: options }
            true
          end

        response = flow_manager.process_conversation(
          message: async_trigger_message,
          context: async_test_context,
          persona: 'buddy'
        )

        expect_async_flow_triggered(response)

        # Wait for completion
        wait_for_async_completion(max_wait: 6.0)

        # Should have both immediate and follow-up TTS
        expect(tts_calls.length).to be >= 1
        expect_thread_cleanup
      end

      it 'handles tool execution failures gracefully' do
        mock_ha_tts_calls
        mock_failed_tool_execution

        response = flow_manager.process_conversation(
          message: async_trigger_message,
          context: async_test_context,
          persona: 'buddy'
        )

        expect_async_flow_triggered(response)

        # Wait for completion (should still complete even with failures)
        wait_for_async_completion(max_wait: 6.0)
        expect_thread_cleanup
      end

      it 'respects configuration timeouts' do
        mock_ha_tts_calls

        # Mock slow tool execution
        allow_any_instance_of(Services::Conversation::ToolExecutionEngine)
          .to receive(:execute_action) do
            sleep(0.2) # Simulate slow execution
            { success: true, result: 'Slow tool executed' }
          end

        start_time = Time.now

        response = flow_manager.process_conversation(
          message: async_trigger_message,
          context: async_test_context,
          persona: 'buddy'
        )

        expect_async_flow_triggered(response)

        # Wait for completion
        wait_for_async_completion(max_wait: 6.0)

        # Verify execution completed within reasonable time
        execution_time = Time.now - start_time
        expect(execution_time).to be < 6.0
        expect_thread_cleanup
      end
    end

    context 'when async tools are disabled' do
      before { simulate_async_disabled }

      it 'falls back to synchronous flow' do
        mock_successful_tool_execution

        response = flow_manager.process_conversation(
          message: async_trigger_message,
          context: async_test_context,
          persona: 'buddy'
        )

        # Should be normal synchronous response
        expect(response).to be_a(Hash)
        expect(response['success']).to be true
        expect(response['data']['response_type']).not_to eq('immediate_speech_with_background_tools')
      end
    end

    context 'in conversation extraction mode' do
      before { simulate_conversation_extraction_mode }

      it 'uses synchronous flow' do
        mock_successful_tool_execution

        response = flow_manager.process_conversation(
          message: async_trigger_message,
          context: async_test_context,
          persona: 'buddy'
        )

        # Should be normal synchronous response
        expect(response).to be_a(Hash)
        expect(response['success']).to be true
        expect(response['data']['response_type']).not_to eq('immediate_speech_with_background_tools')
      end
    end
  end

  describe 'Async Flow Decision Logic' do
    it 'skips async for short messages' do
      response = flow_manager.process_conversation(
        message: 'hi',
        context: async_test_context,
        persona: 'buddy'
      )

      # Short messages should not trigger async
      expect(response['data']['response_type']).not_to eq('immediate_speech_with_background_tools')
    end

    it 'skips async for questions' do
      response = flow_manager.process_conversation(
        message: 'what time is it?',
        context: async_test_context,
        persona: 'buddy'
      )

      # Questions should not trigger async
      expect(response['data']['response_type']).not_to eq('immediate_speech_with_background_tools')
    end

    it 'skips async for follow-up messages' do
      response = flow_manager.process_conversation(
        message: async_trigger_message,
        context: async_test_context.merge(is_follow_up: true),
        persona: 'buddy'
      )

      # Follow-ups should not trigger async
      expect(response['data']['response_type']).not_to eq('immediate_speech_with_background_tools')
    end

    it 'skips async when force_sync is set' do
      response = flow_manager.process_conversation(
        message: async_trigger_message,
        context: async_test_context.merge(force_sync: true),
        persona: 'buddy'
      )

      # force_sync should prevent async
      expect(response['data']['response_type']).not_to eq('immediate_speech_with_background_tools')
    end
  end

  describe 'Thread Management' do
    it 'limits concurrent threads based on configuration' do
      mock_ha_tts_calls
      mock_successful_tool_execution

      max_threads = GlitchCube.config.async_max_threads

      # Start multiple async conversations
      responses = []
      (max_threads + 1).times do |i|
        response = flow_manager.process_conversation(
          message: async_trigger_message,
          context: async_test_context.merge(session_id: "test_session_#{i}"),
          persona: 'buddy'
        )
        responses << response
      end

      # Should not exceed max threads
      expect(@active_threads.size).to be <= max_threads

      # Wait for completion
      wait_for_async_completion(max_wait: 10.0)
      expect_thread_cleanup
    end

    it 'cleans up threads on completion' do
      mock_ha_tts_calls
      mock_successful_tool_execution

      response = flow_manager.process_conversation(
        message: async_trigger_message,
        context: async_test_context,
        persona: 'buddy'
      )

      expect_async_flow_triggered(response)

      # Verify thread was created
      expect(@active_threads).not_to be_empty

      # Wait for completion
      wait_for_async_completion(max_wait: 6.0)

      # Verify cleanup
      expect_thread_cleanup
    end
  end

  # Helper to mock LLM responses with tool actions
  def mock_llm_response_with_tools(response:, actions:)
    allow_any_instance_of(Services::Conversation::LlmInteractionManager)
      .to receive(:generate_response).and_return({
                                                   'response' => response,
                                                   'actions' => actions,
                                                   'metadata' => { 'model' => 'test-model', 'tokens_used' => 100 }
                                                 })
  end
end
