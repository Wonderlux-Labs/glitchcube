# frozen_string_literal: true

# Shared context for testing async conversation flow
# Provides test helpers and configuration for async tool execution testing

RSpec.shared_context 'with async conversation setup' do
  # Override configuration for async tools testing
  before do
    # Enable async tools for testing
    allow(GlitchCube.config).to receive(:async_tools_enabled?).and_return(true)
    allow(GlitchCube.config).to receive(:async_immediate_timeout).and_return(0.1)
    allow(GlitchCube.config).to receive(:async_background_timeout).and_return(5.0)
    allow(GlitchCube.config).to receive(:async_follow_up_delay).and_return(0.1)
    allow(GlitchCube.config).to receive(:async_max_threads).and_return(2)
    allow(GlitchCube.config).to receive(:async_thread_cleanup_timeout).and_return(2.0)
    allow(GlitchCube.config).to receive(:async_fallback_to_sync?).and_return(true)

    # Mock thread storage for tracking active threads
    @active_threads = {}
    allow_any_instance_of(Services::Conversation::FlowManager)
      .to receive(:instance_variable_get).with(:@active_tool_threads).and_return(@active_threads)
  end

  # Helper to wait for async operations to complete
  def wait_for_async_completion(max_wait: 3.0, poll_interval: 0.1)
    start_time = Time.now
    while Time.now - start_time < max_wait
      return true if @active_threads.empty?

      sleep poll_interval
    end
    false
  end

  # Helper to verify immediate response structure
  def expect_immediate_response(response)
    expect(response).to be_a(Hash)
    expect(response).to have_key('success')
    expect(response['success']).to be true
    expect(response).to have_key('data')

    data = response['data']
    expect(data).to have_key('response_type')
    expect(data['response_type']).to eq('immediate_speech_with_background_tools')
    expect(data).to have_key('speech_text')
    expect(data['speech_text']).to be_a(String)
    expect(data['speech_text']).not_to be_empty
  end

  # Helper to mock Home Assistant TTS calls
  def mock_ha_tts_calls
    allow_any_instance_of(Core::HomeAssistantClient)
      .to receive(:speak_with_retry).and_return(true)
    allow_any_instance_of(Core::HomeAssistantClient)
      .to receive(:speak_as_persona).and_return(true)
  end

  # Helper to create test message that should trigger async flow
  def async_trigger_message
    'turn on the lights and play some music'
  end

  # Helper to create test context for async conversation
  def async_test_context
    {
      session_id: 'test_async_session_123',
      conversation_id: 'ha_conversation_456',
      device_id: 'test_device',
      language: 'en-US',
      voice_interaction: true,
      timestamp: Time.now.iso8601
    }
  end

  # Helper to verify thread cleanup
  def expect_thread_cleanup
    expect(@active_threads).to be_empty
  end

  # Helper to mock tool execution success
  def mock_successful_tool_execution
    allow_any_instance_of(Services::Conversation::ToolExecutionEngine)
      .to receive(:execute_action).and_return({
                                                success: true,
                                                result: 'Tool executed successfully',
                                                metadata: { execution_time: 0.5 }
                                              })
  end

  # Helper to mock tool execution failure
  def mock_failed_tool_execution
    allow_any_instance_of(Services::Conversation::ToolExecutionEngine)
      .to receive(:execute_action).and_return({
                                                success: false,
                                                error: 'Tool execution failed',
                                                metadata: { execution_time: 0.2 }
                                              })
  end

  # Helper to create sample tool actions for testing
  def sample_async_actions
    [
      {
        tool: 'lighting_control',
        action: 'turn_on',
        parameters: { entity_id: 'light.test_light', brightness: 255 }
      },
      {
        tool: 'music_control',
        action: 'play',
        parameters: { query: 'relaxing music', volume: 0.7 }
      }
    ]
  end

  # Helper to verify async flow was triggered
  def expect_async_flow_triggered(response)
    expect_immediate_response(response)

    # Verify that background thread was started
    expect(@active_threads).not_to be_empty
  end

  # Helper to simulate conversation extraction mode (sync fallback)
  def simulate_conversation_extraction_mode
    allow(GlitchCube.config).to receive(:tool_execution_mode).and_return(:conversation_extraction)
  end

  # Helper to simulate async disabled
  def simulate_async_disabled
    allow(GlitchCube.config).to receive(:async_tools_enabled?).and_return(false)
  end
end

# Shared examples for async conversation behavior
RSpec.shared_examples 'async conversation flow' do
  include_context 'with async conversation setup'

  it 'triggers async flow for tool-heavy messages' do
    mock_ha_tts_calls
    mock_successful_tool_execution

    message = async_trigger_message
    context = async_test_context

    response = subject.process_conversation(
      message: message,
      context: context,
      persona: 'buddy'
    )

    expect_async_flow_triggered(response)
  end

  it 'falls back to sync when async is disabled' do
    simulate_async_disabled

    message = async_trigger_message
    context = async_test_context

    response = subject.process_conversation(
      message: message,
      context: context,
      persona: 'buddy'
    )

    # Should be normal response, not async
    expect(response).to be_a(Hash)
    expect(response['data']['response_type']).not_to eq('immediate_speech_with_background_tools')
  end

  it 'falls back to sync in conversation extraction mode' do
    simulate_conversation_extraction_mode

    message = async_trigger_message
    context = async_test_context

    response = subject.process_conversation(
      message: message,
      context: context,
      persona: 'buddy'
    )

    # Should be normal response, not async
    expect(response).to be_a(Hash)
    expect(response['data']['response_type']).not_to eq('immediate_speech_with_background_tools')
  end

  it 'cleans up threads after completion' do
    mock_ha_tts_calls
    mock_successful_tool_execution

    message = async_trigger_message
    context = async_test_context

    response = subject.process_conversation(
      message: message,
      context: context,
      persona: 'buddy'
    )

    expect_async_flow_triggered(response)

    # Wait for background completion
    expect(wait_for_async_completion(max_wait: 6.0)).to be true
    expect_thread_cleanup
  end
end
