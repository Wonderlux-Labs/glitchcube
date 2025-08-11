#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../config/environment'

# Test the model splitting functionality
# First call uses tools model, second call uses conversation model

puts 'Testing Model Split Configuration'
puts '================================='
puts "Default Model: #{GlitchCube.config.ai.default_model}"
puts "Tools Model: #{GlitchCube.config.ai.default_tools_model}"
puts "Models are #{GlitchCube.config.ai.default_model == GlitchCube.config.ai.default_tools_model ? 'SAME' : 'DIFFERENT'}"
puts
puts "Set ENV['DEFAULT_TOOLS_MODEL'] to use a different model for tools"
puts "Example: DEFAULT_TOOLS_MODEL='openai/gpt-4.1-mini' ruby #{__FILE__}"
puts

# Create a conversation module instance
module_instance = ConversationModule.new

# Test message that should trigger tool usage
test_message = 'Turn the lights blue and tell me a joke'

context = {
  session_id: "test-model-split-#{Time.now.to_i}",
  tools: [
    {
      type: 'function',
      function: {
        name: 'control_lights',
        description: 'Control the LED lights',
        parameters: {
          type: 'object',
          properties: {
            color: { type: 'string', description: 'Color to set the lights to' },
            brightness: { type: 'integer', description: 'Brightness level 0-100' }
          },
          required: ['color']
        }
      }
    }
  ]
}

puts "Sending test message: '#{test_message}'"
puts 'With tools enabled to test model splitting...'
puts

begin
  response = module_instance.call(
    message: test_message,
    context: context
  )

  puts 'Response received!'
  puts '=================='
  puts "Text: #{response[:response]}"
  puts 'Model Used: Check logs for model details'
  puts "Tool Calls: #{response[:tool_calls]&.size || 0}"
  puts "Cost: $#{response[:cost]}"
  puts
  puts 'Check logs/conversation.log for detailed model usage:'
  puts "- First call (tools): Should use #{GlitchCube.config.ai.default_tools_model}"
  puts "- Second call (conversation): Should use #{GlitchCube.config.ai.default_model}"
rescue StandardError => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end
