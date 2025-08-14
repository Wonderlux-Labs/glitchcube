# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'HomeAssistantToolProxy VCR Integration', :vcr do
  let(:proxy) { Services::Conversation::HomeAssistantToolProxy.new }
  let(:session_id) { 'vcr-test-session-123' }

  # Real LLM response with tool calls - NO MOCKS!
  let(:real_llm_response) do
    # Create real LLM response object with tool call structure
    raw_response = {
      choices: [{
        message: {
          role: 'assistant',
          content: nil,
          tool_calls: [
            {
              id: 'call_turn_on_lights',
              type: 'function',
              function: {
                name: 'turn_on_light',
                arguments: '{"entity_id": "light.living_room"}'
              }
            },
            {
              id: 'call_speak_message',
              type: 'function',
              function: {
                name: 'speak',
                arguments: '{"message": "The lights are now on", "voice": "Josh"}'
              }
            }
          ]
        }
      }],
      usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 }
    }

    Services::Llm::LLMResponse.new(raw_response)
  end

  # FORCE BIFURCATION: Mock config to use back_to_hass pattern
  before do
    allow(GlitchCube.config).to receive(:tool_calling_pattern).and_return(:back_to_hass)
  end

  # Complex real LLM response for formatting tests
  let(:complex_real_llm_response) do
    raw_response = {
      choices: [{
        message: {
          role: 'assistant',
          content: nil,
          tool_calls: [
            {
              id: 'call_1',
              type: 'function',
              function: {
                name: 'turn_on_light',
                arguments: '{"entity_id": "light.bedroom"}'
              }
            },
            {
              id: 'call_2',
              type: 'function',
              function: {
                name: 'set_light_brightness',
                arguments: '{"entity_id": "light.bedroom", "brightness": 75}'
              }
            },
            {
              id: 'call_3',
              type: 'function',
              function: {
                name: 'speak',
                arguments: '{"message": "Bedroom lights adjusted", "voice": "Rachel"}'
              }
            },
            {
              id: 'call_4',
              type: 'function',
              function: {
                name: 'display_text',
                arguments: '{"text": "💡 Lights: 75%"}'
              }
            }
          ]
        }
      }],
      usage: { prompt_tokens: 150, completion_tokens: 75, total_tokens: 225 }
    }

    Services::Llm::LLMResponse.new(raw_response)
  end

  describe 'actual Home Assistant conversation agent call', vcr: { cassette_name: 'home_assistant_tool_proxy/claude_conversation_agent_call' } do
    it 'sends formatted tool requests to claude conversation agent and processes unified response' do
      result = proxy.execute_via_hass(real_llm_response, session_id)

      # Basic structure validation
      expect(result).to be_a(Hash)
      expect(result).to have_key(:tool_results)
      expect(result).to have_key(:last_tool_calls)
      expect(result).to have_key(:failed_tool_calls)

      # Should have SINGLE unified result (not individual tool results)
      expect(result[:tool_results]).to have_attributes(count: 1)
      expect(result[:last_tool_calls]).to have_attributes(count: 1)

      # Check that unified tool result has expected structure
      unified_result = result[:tool_results].first
      expect(unified_result).to include(:tool_call_id, :role, :name, :content)
      expect(unified_result[:role]).to eq('tool')
      expect(unified_result[:name]).to eq('home_assistant_tool_execution')
      expect(unified_result[:tool_call_id]).to eq('hass_unified_execution')

      # Content should be valid JSON with HA Claude response
      expect { JSON.parse(unified_result[:content]) }.not_to raise_error

      parsed_content = JSON.parse(unified_result[:content])
      expect(parsed_content).to include('success', 'message', 'executed_via', 'executed_tools')
      expect(parsed_content['executed_via']).to eq('home_assistant_claude_conversation_agent')
      expect(parsed_content['executed_tools']).to eq(%w[turn_on_light speak])

      # Log what we actually got back for analysis - REAL HA RESPONSE DATA!
      puts "\n#{'=' * 80}"
      puts 'HOME ASSISTANT UNIFIED TOOL PROXY VCR TEST RESULTS'
      puts '=' * 80
      puts "Tool Results Count: #{result[:tool_results].count} (should be 1 unified result)"
      puts "Failed Tool Calls: #{result[:failed_tool_calls].count}"

      puts "\nUnified Tool Result:"
      unified_result = result[:tool_results].first
      puts "  Name: #{unified_result[:name]}"
      puts "  Call ID: #{unified_result[:tool_call_id]}"
      puts "  Content: #{unified_result[:content]}"

      puts "\nParsed Unified Content:"
      parsed_content = JSON.parse(unified_result[:content])
      puts "  Success: #{parsed_content['success']}"
      puts "  Message: #{parsed_content['message']}"
      puts "  Executed Via: #{parsed_content['executed_via']}"
      puts "  Tools Executed: #{parsed_content['executed_tools'].join(', ')}"
      puts "  Summary: #{parsed_content['execution_summary']}"

      puts "\nLast Tool Call (Unified):"
      last_call = result[:last_tool_calls].first
      puts "  Tool Name: #{last_call[:tool_name]}"
      puts "  Result Message: #{last_call[:result]['message']}"
      puts "#{'=' * 80}\n"
    end
  end

  describe 'natural language formatting', vcr: { cassette_name: 'home_assistant_tool_proxy/complex_tool_formatting_check' } do
    it 'formats different tool types appropriately for conversation agent and returns unified response' do
      result = proxy.execute_via_hass(complex_real_llm_response, session_id)

      # Should have SINGLE unified result regardless of number of input tools
      expect(result[:tool_results]).to have_attributes(count: 1)

      unified_result = result[:tool_results].first
      parsed_content = JSON.parse(unified_result[:content])
      expect(parsed_content['executed_tools']).to eq(%w[turn_on_light set_light_brightness speak display_text])

      # Log the complex formatting results with REAL HA DATA
      puts "\n#{'=' * 80}"
      puts 'COMPLEX UNIFIED TOOL FORMATTING VCR TEST'
      puts '=' * 80
      puts 'Tools requested (4 individual tools):'
      puts '1. turn_on_light (light.bedroom)'
      puts '2. set_light_brightness (light.bedroom, 75%)'
      puts "3. speak ('Bedroom lights adjusted', Rachel voice)"
      puts "4. display_text ('💡 Lights: 75%')"

      puts "\nHome Assistant Unified Response Processing:"
      unified_result = result[:tool_results].first
      content = JSON.parse(unified_result[:content])
      puts "  Unified Execution: #{content['success'] ? 'SUCCESS' : 'FAILED'}"
      puts "  Tools Executed: #{content['executed_tools'].join(', ')}"
      puts "  HA Response Message: #{content['message']}"
      puts "  Execution Summary: #{content['execution_summary']}"
      puts "#{'=' * 80}\n"
    end
  end

  describe 'error handling', vcr: { cassette_name: 'home_assistant_tool_proxy/error_scenarios' } do
    it 'handles cases where conversation agent is not available or fails' do
      # Test with a session ID that might cause issues
      error_session_id = 'error-test-session-invalid-agent'

      # This should either work or gracefully handle the error
      result = proxy.execute_via_hass(real_llm_response, error_session_id)

      # Should always return the expected structure, even on error
      expect(result).to be_a(Hash)
      expect(result).to have_key(:tool_results)
      expect(result).to have_key(:last_tool_calls)
      expect(result).to have_key(:failed_tool_calls)

      # Log error handling results with REAL HA ERROR DATA
      puts "\n#{'=' * 80}"
      puts 'ERROR HANDLING VCR TEST'
      puts '=' * 80
      puts "Session ID: #{error_session_id}"
      puts "Tool Results Count: #{result[:tool_results].count}"
      puts "Failed Calls Count: #{result[:failed_tool_calls].count}"

      if result[:tool_results].any?
        result[:tool_results].each_with_index do |tr, i|
          content = begin
            JSON.parse(tr[:content])
          rescue StandardError
            tr[:content]
          end
          puts "\nResult #{i + 1}:"
          puts "  Name: #{tr[:name]}"
          puts "  Success: #{content.is_a?(Hash) ? content['success'] : 'unknown'}"
          puts "  Content: #{content.is_a?(Hash) ? content['message'] || content['error'] : content}"
        end
      end

      if result[:failed_tool_calls].any?
        puts "\nFailed Tool Calls:"
        result[:failed_tool_calls].each do |failed|
          puts "  - #{failed[:function_name]}: #{failed[:error]}"
        end
      end
      puts "#{'=' * 80}\n"
    end
  end
end
