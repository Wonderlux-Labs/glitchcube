#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'app'

puts "🔍 Testing Conversation Tracing..."
puts "Environment: #{GlitchCube.config.environment}"
puts "Tracing enabled: #{GlitchCube.config.conversation_tracing_enabled?}"

conversation_module = ConversationModule.new

# Enable debug output
ENV['DEBUG'] = 'true'

puts "\n🚀 Starting conversation..."
result = conversation_module.call(
  message: 'Hello, tell me about art',
  context: {
    session_id: 'manual-test-123',
    trace_conversation: true
  },
  persona: 'playful'
)

puts "\n📊 RESULT:"
puts "Response: #{result[:response]&.length} chars"
puts "Session ID: #{result[:session_id]}"
puts "Trace ID: #{result[:trace_id]}"
puts "Cost: $#{result[:cost]}"
puts "Error: #{result[:error]}" if result[:error]

if result[:trace_id]
  puts "\n🔍 RETRIEVING TRACE:"
  trace = Services::ConversationTracer.get_trace(result[:trace_id])
  
  if trace
    puts "✅ Trace retrieved successfully"
    puts "Total steps: #{trace[:total_steps]}"
    puts "Duration: #{trace[:total_duration_ms]}ms"
    puts "Services: #{trace[:traces].map { |t| t[:service] }.uniq.join(', ')}"
    
    puts "\nStep-by-step trace:"
    trace[:traces].each_with_index do |step, i|
      puts "  #{i+1}. #{step[:service]}.#{step[:action]}"
      puts "     Time: +#{step[:timing_ms]}ms, Success: #{step[:success]}"
      if step[:data][:model]
        puts "     Model: #{step[:data][:model]}, Cost: $#{step[:data][:cost]}"
      end
    end
  else
    puts "❌ Trace could not be retrieved"
  end
else
  puts "❌ No trace ID returned"
end

puts "\n🧪 Test completed."