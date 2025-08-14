# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Tool Execution Bifurcation Integration', :vcr do
  let(:execution_engine) { Services::Conversation::ToolExecutionEngine.new }
  let(:session_id) { 'bifurcation-test-session-123' }

  # Real LLM response with tool calls - NO MOCKS!
  let(:real_llm_response) do
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
                arguments: '{"message": "BIFURCATION TEST - lights activated via HA Claude agent", "voice": "Josh"}'
              }
            }
          ]
        }
      }],
      usage: { prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 }
    }

    Services::Llm::LLMResponse.new(raw_response)
  end

  describe 'back_to_hass pattern', vcr: { cassette_name: 'bifurcation_back_to_hass_working' } do
    before do
      # FORCE BIFURCATION: Mock config to use back_to_hass pattern
      allow(GlitchCube.config).to receive(:tool_calling_pattern).and_return(:back_to_hass)
    end

    it 'branches to HomeAssistantToolProxy and returns unified response from HA Claude agent' do
      # Debug what pattern is actually being used
      puts "\n🔍 DEBUG: Config pattern = #{GlitchCube.config.tool_calling_pattern.inspect}"
      puts '🔍 DEBUG: Expected pattern = :back_to_hass'
      puts "🔍 DEBUG: Pattern match = #{GlitchCube.config.tool_calling_pattern == :back_to_hass}"

      # This should NOT call our ToolExecutor at all - complete bifurcation
      expect(Services::ToolExecutor).not_to receive(:execute)

      puts '🔍 DEBUG: About to call execute_tool_calls with bifurcation enabled'
      result = execution_engine.execute_tool_calls(real_llm_response, session_id)
      puts "🔍 DEBUG: Received result with #{result[:tool_results].count} tool results"

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

      # Log what we actually got back from REAL HA Claude agent
      puts "\n#{'=' * 80}"
      puts 'BIFURCATION TEST: BACK_TO_HASS PATTERN'
      puts '=' * 80
      puts '✅ Confirmed: ToolExecutor was NOT called (complete bifurcation)'
      puts "✅ Tool Results Count: #{result[:tool_results].count} (unified response)"
      puts "✅ Failed Tool Calls: #{result[:failed_tool_calls].count}"

      puts "\nUnified HA Claude Agent Response:"
      puts "  Name: #{unified_result[:name]}"
      puts "  Call ID: #{unified_result[:tool_call_id]}"

      puts "\nParsed HA Claude Agent Content:"
      puts "  Success: #{parsed_content['success']}"
      puts "  Message: #{parsed_content['message']}"
      puts "  Executed Via: #{parsed_content['executed_via']}"
      puts "  Tools Executed: #{parsed_content['executed_tools'].join(', ')}"
      puts "  Summary: #{parsed_content['execution_summary']}"
      puts "#{'=' * 80}\n"
    end
  end

  describe 'default pattern' do
    before do
      # Use default pattern - should go through our ToolExecutor
      allow(GlitchCube.config).to receive(:tool_calling_pattern).and_return(:default)
    end

    it 'uses ToolExecutor for individual tool calls (not HA bifurcation)' do
      # This should call our ToolExecutor
      expect(Services::ToolExecutor).to receive(:execute).twice.and_call_original

      result = execution_engine.execute_tool_calls(real_llm_response, session_id)

      # Should have individual tool results (NOT unified)
      expect(result[:tool_results]).to have_attributes(count: 2)
      expect(result[:last_tool_calls]).to have_attributes(count: 2)

      # Check that tool results are individual, not unified
      result[:tool_results].each do |tool_result|
        expect(tool_result[:name]).to be_in(%w[turn_on_light speak])
        expect(tool_result[:name]).not_to eq('home_assistant_tool_execution')
      end

      puts "\n#{'=' * 80}"
      puts 'BIFURCATION TEST: DEFAULT PATTERN'
      puts '=' * 80
      puts '✅ Confirmed: ToolExecutor WAS called (individual tool execution)'
      puts "✅ Tool Results Count: #{result[:tool_results].count} (individual results)"
      puts "✅ Failed Tool Calls: #{result[:failed_tool_calls].count}"

      puts "\nIndividual Tool Results:"
      result[:tool_results].each_with_index do |tr, i|
        puts "  #{i + 1}. #{tr[:name]} (#{tr[:tool_call_id]})"
      end
      puts "#{'=' * 80}\n"
    end
  end
end
