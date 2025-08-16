# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Debug Home Assistant Conversation API', :vcr do
  let(:ha_client) { Services::Core::HomeAssistantClient.new }

  before do
    allow(Services::Logging::SimpleLogger).to receive(:info)
    allow(Services::Logging::SimpleLogger).to receive(:debug)
    allow(Services::Logging::SimpleLogger).to receive(:warn)
    allow(Services::Logging::SimpleLogger).to receive(:log_error)
  end

  describe 'basic conversation agent call', vcr: { cassette_name: 'debug_ha_conversation/basic_agent_call' } do
    # FIXME: VCR cassette is stale - URLs/endpoints have changed
    # This is a debug integration test that requires live Home Assistant instance
    # Re-record cassettes when HA instance is available for testing
    xit 'makes a simple call to the conversation agent without specific agent_id' do
      response = ha_client.process_voice_command(
        'Turn on the living room lights',
        return_response: true
      )

      puts "\n#{'=' * 80}"
      puts 'BASIC HOME ASSISTANT CONVERSATION API TEST'
      puts '=' * 80
      puts "Request: 'Turn on the living room lights'"
      puts "Response Class: #{response.class}"
      puts 'Response Content:'
      puts response.inspect
      puts "#{'=' * 80}\n"

      expect(response).to be_present
    end
  end

  describe 'specific agent call', vcr: { cassette_name: 'debug_ha_conversation/specific_agent_call' } do
    # FIXME: VCR cassette is stale - URLs/endpoints have changed
    # This debug test tries to call conversation.claude_background which may no longer exist
    # Re-record cassettes when HA instance is available for testing
    xit 'attempts to call the claude background agent specifically' do
      response = ha_client.process_voice_command(
        'Please execute these tools: 1. Turn on light.living_room 2. Say "Hello world"',
        agent_id: 'conversation.claude_background',
        return_response: true
      )

      puts "\n#{'=' * 80}"
      puts 'SPECIFIC AGENT HOME ASSISTANT CONVERSATION TEST'
      puts '=' * 80
      puts 'Request: Multi-tool request to claude background agent'
      puts 'Agent ID: conversation.claude_background'
      puts "Response Class: #{response.class}"
      puts 'Response Content:'
      puts response.inspect
      puts "#{'=' * 80}\n"

      expect(response).to be_present
    end
  end

  describe 'conversation with session tracking', vcr: { cassette_name: 'debug_ha_conversation/session_tracking' } do
    # FIXME: VCR cassette is stale - URLs/endpoints have changed
    # This is a debug integration test that requires live Home Assistant instance
    # Re-record cassettes when HA instance is available for testing
    xit 'makes a call with conversation_id for session tracking' do
      session_id = 'debug-test-session-123'

      response = ha_client.process_voice_command(
        'Execute turn_on_light for light.bedroom',
        conversation_id: session_id,
        return_response: true
      )

      puts "\n#{'=' * 80}"
      puts 'SESSION TRACKING HOME ASSISTANT CONVERSATION TEST'
      puts '=' * 80
      puts 'Request: Tool execution with session tracking'
      puts "Session ID: #{session_id}"
      puts "Response Class: #{response.class}"
      puts 'Response Content:'
      puts response.inspect
      puts "#{'=' * 80}\n"

      expect(response).to be_present
    end
  end

  describe 'error handling', vcr: { cassette_name: 'debug_ha_conversation/error_handling' } do
    # FIXME: VCR cassette is stale - URLs/endpoints have changed
    # This is a debug integration test that requires live Home Assistant instance
    # Re-record cassettes when HA instance is available for testing
    xit 'handles invalid agent_id gracefully' do
      response = ha_client.process_voice_command(
        'Turn on lights',
        agent_id: 'conversation.nonexistent_agent',
        return_response: true
      )

      puts "\n#{'=' * 80}"
      puts 'ERROR HANDLING HOME ASSISTANT CONVERSATION TEST'
      puts '=' * 80
      puts 'Request: Call to nonexistent agent'
      puts 'Agent ID: conversation.nonexistent_agent'
      puts "Response Class: #{response.class}"
      puts 'Response Content:'
      puts response.inspect
      puts "#{'=' * 80}\n"

      expect(response).to be_present
    rescue StandardError => e
      puts "\n#{'=' * 80}"
      puts 'ERROR HANDLING - EXCEPTION CAUGHT'
      puts '=' * 80
      puts "Error Class: #{e.class}"
      puts "Error Message: #{e.message}"
      puts "#{'=' * 80}\n"

      expect(e).to be_a(StandardError)
    end
  end
end
