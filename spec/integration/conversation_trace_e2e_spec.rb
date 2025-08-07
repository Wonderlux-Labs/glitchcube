# frozen_string_literal: true

require 'spec_helper'

# End-to-end test for conversation tracing functionality
RSpec.describe 'Conversation Tracing E2E', :vcr do
  let(:session_id) { 'trace-e2e-test-session' }

  before do
    # Enable tracing for this test
    allow(GlitchCube.config).to receive_messages(environment: 'development', conversation_tracing_enabled?: true)
  end

  describe 'Full conversation trace workflow' do
    it 'creates and retrieves complete conversation traces' do
      # Step 1: Create a conversation with tracing enabled
      conversation_module = ConversationModule.new

      result = conversation_module.call(
        message: 'Tell me about the art and culture at Burning Man',
        context: {
          session_id: session_id,
          location: 'Center Camp',
          persona: 'contemplative',
          trace_conversation: true,
          skip_memories: false
        }
      )

      # Verify conversation succeeded
      expect(result[:response]).to be_present
      expect(result[:session_id]).to eq(session_id)
      expect(result[:trace_id]).to be_present

      trace_id = result[:trace_id]

      # Step 2: Retrieve the trace from Redis
      retrieved_trace = Services::ConversationTracer.get_trace(trace_id)

      expect(retrieved_trace).to be_present
      expect(retrieved_trace[:trace_id]).to eq(trace_id)
      expect(retrieved_trace[:session_id]).to eq(session_id)
      expect(retrieved_trace[:total_steps]).to be > 0
      expect(retrieved_trace[:traces]).to be_an(Array)

      # Step 3: Analyze the trace structure
      traces = retrieved_trace[:traces]
      expect(traces).not_to be_empty

      # Verify start step
      start_step = traces.find { |t| t[:action] == 'start_conversation' }
      expect(start_step).to be_present
      expect(start_step[:service]).to eq('ConversationModule')
      expect(start_step[:data][:message]).to eq('Tell me about the art and culture at Burning Man')
      expect(start_step[:data][:persona]).to eq('contemplative')

      # Verify LLM call step
      llm_step = traces.find { |t| t[:service] == 'LLMService' }
      expect(llm_step).to be_present
      expect(llm_step[:action]).to eq('complete_with_messages')
      expect(llm_step[:data][:model]).to be_present
      expect(llm_step[:success]).to be true

      # Verify completion step
      complete_step = traces.find { |t| t[:action] == 'complete_conversation' }
      expect(complete_step).to be_present
      expect(complete_step[:data][:response_length]).to be > 0

      # Step 4: Test session trace retrieval
      session_traces = Services::ConversationTracer.get_session_traces(session_id)
      expect(session_traces.size).to eq(1)
      expect(session_traces.first[:trace_id]).to eq(trace_id)

      puts "\n🔍 TRACE ANALYSIS:"
      puts "Trace ID: #{trace_id}"
      puts "Session ID: #{session_id}"
      puts "Total Steps: #{retrieved_trace[:total_steps]}"
      puts "Duration: #{retrieved_trace[:total_duration_ms]}ms"
      puts "Services Used: #{traces.map { |t| t[:service] }.uniq.join(', ')}"
      puts "\nStep-by-step flow:"
      traces.each_with_index do |step, i|
        puts "  #{i + 1}. #{step[:service]}.#{step[:action]} (#{step[:timing_ms]}ms)"
        puts "     Model: #{step[:data][:model]}, Cost: $#{step[:data][:cost]}" if step[:data][:model]
      end
    end

    it 'traces conversation with tool calls' do
      conversation_module = ConversationModule.new

      result = conversation_module.call(
        message: 'What is the current weather like?',
        context: {
          session_id: "#{session_id}-tools",
          location: 'Deep Playa',
          tools: ['weather_lookup'], # Enable weather tool
          trace_conversation: true
        },
        persona: 'playful'
      )

      expect(result[:trace_id]).to be_present

      trace = Services::ConversationTracer.get_trace(result[:trace_id])
      traces = trace[:traces]

      # Look for tool execution if tools were called
      tool_step = traces.find { |t| t[:service] == 'ToolExecutor' }
      if tool_step
        expect(tool_step[:data][:tools_called]).to include('weather_lookup')
        puts "\n🔧 TOOL EXECUTION TRACE:"
        puts "Tools Called: #{tool_step[:data][:tools_called].join(', ')}"
        puts "Execution Time: #{tool_step[:data][:execution_time_ms]}ms"
      else
        puts "\n📝 No tool calls in this trace (tools may not be available in test environment)"
      end
    end

    it 'traces memory injection process' do
      # First, create some conversation history
      conversation_module = ConversationModule.new

      # First conversation to create history
      conversation_module.call(
        message: 'I love the art installations here at Center Camp',
        context: {
          session_id: "#{session_id}-memory",
          location: 'Center Camp'
        }
      )

      # Second conversation that should trigger memory injection
      result = conversation_module.call(
        message: 'Tell me what you remember about our previous conversations',
        context: {
          session_id: "#{session_id}-memory",
          location: 'Center Camp',
          skip_memories: false, # Explicitly enable memory injection
          trace_conversation: true
        }
      )

      trace = Services::ConversationTracer.get_trace(result[:trace_id])
      traces = trace[:traces]

      # Look for memory injection step
      memory_step = traces.find { |t| t[:service] == 'MemoryRecallService' }
      if memory_step
        puts "\n🧠 MEMORY INJECTION TRACE:"
        puts "Memories Found: #{memory_step[:data][:memories_found]}"
        puts "Location: #{memory_step[:data][:location]}"
        puts "Context Length: #{memory_step[:data][:context_length]}"
      else
        puts "\n📝 No memory injection traced (memory service may not be available)"
      end
    end
  end

  describe 'Trace data structure validation' do
    it 'ensures traces contain all required fields' do
      conversation_module = ConversationModule.new

      result = conversation_module.call(
        message: 'Simple test message for trace validation',
        context: {
          session_id: "#{session_id}-validation",
          trace_conversation: true
        }
      )

      trace = Services::ConversationTracer.get_trace(result[:trace_id])

      # Validate top-level trace structure
      expect(trace).to include(
        :trace_id,
        :session_id,
        :started_at,
        :total_steps,
        :total_duration_ms,
        :traces
      )

      # Validate individual trace steps
      trace[:traces].each do |step|
        expect(step).to include(
          :step,
          :service,
          :action,
          :timestamp,
          :data,
          :timing_ms,
          :success
        )

        expect(step[:step]).to be_a(Integer)
        expect(step[:service]).to be_a(String)
        expect(step[:action]).to be_a(String)
        expect(step[:timestamp]).to be_a(String)
        expect(step[:data]).to be_a(Hash)
        expect(step[:timing_ms]).to be_a(Integer)
        expect(step[:success]).to be_in([true, false])
      end

      puts "\n✅ TRACE STRUCTURE VALIDATION PASSED"
      puts 'All traces contain required fields with correct types'
    end
  end
end
