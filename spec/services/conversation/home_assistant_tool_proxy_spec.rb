# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::Conversation::HomeAssistantToolProxy do
  let(:ha_client) { instance_double(Core::HomeAssistantClient) }
  let(:proxy) { described_class.new(ha_client: ha_client) }
  let(:session_id) { 'test-session-123' }

  # Mock LLM response with tool calls
  let(:mock_llm_response) do
    instance_double('LlmResponse').tap do |response|
      allow(response).to receive(:tool_calls).and_return([
                                                           { id: 'call_1', function: { name: 'turn_on_light' } },
                                                           { id: 'call_2', function: { name: 'speak' } }
                                                         ])
      allow(response).to receive(:function_calls).and_return([
                                                               { name: 'turn_on_light' },
                                                               { name: 'speak' }
                                                             ])
      allow(response).to receive(:function_arguments_for).with('turn_on_light').and_return({ 'entity_id' => 'light.living_room' })
      allow(response).to receive(:function_arguments_for).with('speak').and_return({ 'message' => 'Hello world', 'voice' => 'Josh' })
    end
  end

  before do
    allow(Services::Logging::SimpleLogger).to receive(:info)
    allow(Services::Logging::SimpleLogger).to receive(:debug)
    allow(Services::Logging::SimpleLogger).to receive(:warn)
    allow(Services::Logging::SimpleLogger).to receive(:log_error)
  end

  describe '#execute_via_hass' do
    context 'when Home Assistant responds successfully' do
      let(:ha_response) do
        # Current implementation expects a String response, not Hash with nested structure
        "I've successfully turned on the light in the living room and spoke the message using Josh voice."
      end

      before do
        allow(ha_client).to receive(:process_voice_command).and_return(ha_response)
      end

      it 'formats tool calls as natural language and sends to Home Assistant' do
        result = proxy.execute_via_hass(mock_llm_response, session_id)

        # Check that it calls HA with the correct agent and format
        expect(ha_client).to have_received(:process_voice_command).with(
          match(/BACKGROUND AGENT REQUEST.*Turn on light.living_room.*Say "Hello world" in Josh voice/m),
          agent_id: 'conversation.claude_conversation',
          conversation_id: session_id,
          return_response: true
        )

        # Current implementation returns a unified result, not individual tool results
        expect(result).to include(
          tool_results: array_including(
            hash_including(
              tool_call_id: 'hass_unified_execution',
              role: 'tool',
              name: 'home_assistant_tool_execution',
              content: match(/success.*true/)
            )
          ),
          last_tool_calls: array_including(
            hash_including(tool_name: 'home_assistant_tool_execution')
          ),
          failed_tool_calls: []
        )
      end

      it 'logs the execution process' do
        proxy.execute_via_hass(mock_llm_response, session_id)

        # Current implementation uses emoji-rich logging with different tags
        expect(Services::Logging::SimpleLogger).to have_received(:info).with(
          '🏠 Starting UNIFIED tool execution via Home Assistant Claude agent',
          tagged: %i[conversation tools hass_proxy unified],
          session_id: session_id,
          tool_count: 2,
          architecture: 'back_to_hass'
        )

        expect(Services::Logging::SimpleLogger).to have_received(:info).with(
          match(/🏁 Finished UNIFIED HA tool execution/),
          tagged: %i[conversation tools hass_proxy unified complete],
          session_id: session_id,
          duration_ms: anything,
          unified_response_created: true
        )
      end
    end

    context 'when Home Assistant call fails' do
      before do
        allow(ha_client).to receive(:process_voice_command).and_raise(StandardError, 'HA connection failed')
      end

      it 'returns error results for all tool calls' do
        result = proxy.execute_via_hass(mock_llm_response, session_id)

        # Current implementation returns individual error results for each tool
        expect(result[:tool_results]).to all(
          include(
            role: 'tool',
            content: match(/HA connection failed/)
          )
        )

        expect(result[:failed_tool_calls]).to have_attributes(count: 2)
        expect(Services::Logging::SimpleLogger).to have_received(:log_error)
      end
    end

    context 'with different tool types' do
      let(:light_response) do
        instance_double('LlmResponse').tap do |response|
          allow(response).to receive(:tool_calls).and_return([{ id: 'call_1', function: { name: 'turn_on_light' } }])
          allow(response).to receive(:function_calls).and_return([{ name: 'turn_on_light' }])
          allow(response).to receive(:function_arguments_for).with('turn_on_light').and_return({ 'entity_id' => 'light.bedroom' })
        end
      end

      it 'formats light tools correctly' do
        allow(ha_client).to receive(:process_voice_command).and_return('Light turned on')

        proxy.execute_via_hass(light_response, session_id)

        expect(ha_client).to have_received(:process_voice_command).with(
          match(/BACKGROUND AGENT REQUEST.*Turn on light.bedroom/m),
          agent_id: 'conversation.claude_conversation',
          conversation_id: session_id,
          return_response: true
        )
      end
    end
  end

  describe '#format_tool_calls_as_text' do
    let(:formatted_request) { proxy.send(:format_tool_calls_as_text, mock_llm_response) }

    it 'creates readable instructions for the conversation agent' do
      # Current implementation uses BACKGROUND AGENT REQUEST format
      expect(formatted_request).to include('BACKGROUND AGENT REQUEST - DO NOT SPEAK OUT LOUD OR USE TTS:')
      expect(formatted_request).to include('We have a request from a user to:')
      expect(formatted_request).to include('1. Turn on light.living_room')
      expect(formatted_request).to include('2. Say "Hello world" in Josh voice')
      expect(formatted_request).to include('DO NOT speak out loud, DO NOT use text-to-speech')
    end
  end

  # NOTE: parse_hass_response method was removed in current implementation
  # Response parsing is now handled by extract_response_text and create_unified_tool_result
end
