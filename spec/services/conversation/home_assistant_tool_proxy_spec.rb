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
        {
          'text' => "1. Successfully turned on light.living_room\n2. Spoke message with Josh voice",
          'response' => 'Tasks completed successfully'
        }
      end

      before do
        allow(ha_client).to receive(:process_voice_command).and_return(ha_response)
      end

      it 'formats tool calls as natural language and sends to Home Assistant' do
        result = proxy.execute_via_hass(mock_llm_response, session_id)

        expect(ha_client).to have_received(:process_voice_command).with(
          text: match(/Please execute these tools and report the results:/),
          agent_id: 'conversation.claude_background',
          conversation_id: session_id,
          return_response: true
        )

        expect(result).to include(
          tool_results: array_including(
            hash_including(
              tool_call_id: 'call_1',
              role: 'tool',
              name: 'turn_on_light',
              content: match(/success.*true/)
            ),
            hash_including(
              tool_call_id: 'call_2',
              role: 'tool',
              name: 'speak',
              content: match(/success.*true/)
            )
          ),
          last_tool_calls: array_including(
            hash_including(tool_name: 'turn_on_light'),
            hash_including(tool_name: 'speak')
          ),
          failed_tool_calls: []
        )
      end

      it 'logs the execution process' do
        proxy.execute_via_hass(mock_llm_response, session_id)

        expect(Services::Logging::SimpleLogger).to have_received(:info).with(
          'Starting tool execution via Home Assistant',
          tagged: %i[conversation tools hass_proxy],
          session_id: session_id,
          tool_count: 2
        )

        expect(Services::Logging::SimpleLogger).to have_received(:info).with(
          match(/Finished HA tool execution cycle/),
          tagged: %i[conversation tools hass_proxy],
          session_id: session_id,
          duration_ms: anything,
          tool_results_count: 2
        )
      end
    end

    context 'when Home Assistant call fails' do
      before do
        allow(ha_client).to receive(:process_voice_command).and_raise(StandardError, 'HA connection failed')
      end

      it 'returns error results for all tool calls' do
        result = proxy.execute_via_hass(mock_llm_response, session_id)

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
        allow(ha_client).to receive(:process_voice_command).and_return({ 'text' => 'Light turned on' })

        proxy.execute_via_hass(light_response, session_id)

        expect(ha_client).to have_received(:process_voice_command).with(
          text: match(/Turn on light.bedroom/),
          agent_id: 'conversation.claude_background',
          conversation_id: session_id,
          return_response: true
        )
      end
    end
  end

  describe '#format_tool_calls_as_text' do
    let(:formatted_request) { proxy.send(:format_tool_calls_as_text, mock_llm_response) }

    it 'creates readable instructions for the conversation agent' do
      expect(formatted_request).to include('Please execute these tools and report the results:')
      expect(formatted_request).to include('1. Turn on light.living_room')
      expect(formatted_request).to include('2. Say "Hello world" in Josh voice')
    end
  end

  describe '#parse_hass_response' do
    let(:ha_response) { { 'text' => "1. Light turned on successfully\n2. Message spoken" } }
    let(:result) { proxy.send(:parse_hass_response, ha_response, mock_llm_response, session_id) }

    it 'extracts tool results from Home Assistant response' do
      tool_results, last_tool_calls = result

      expect(tool_results).to have_attributes(count: 2)
      expect(tool_results.first).to include(
        tool_call_id: 'call_1',
        role: 'tool',
        name: 'turn_on_light'
      )

      expect(last_tool_calls).to have_attributes(count: 2)
      expect(last_tool_calls.first[:tool_name]).to eq('turn_on_light')
    end
  end
end
