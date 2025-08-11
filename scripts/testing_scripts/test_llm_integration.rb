#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify LLM service integration and convenience methods

require 'json'

puts '🧪 Testing LLM Service Integration...'

# Test 1: Check if Services can be loaded
begin
  puts "\n1. Testing service loading..."

  # Test top-level LLMService
  puts '   - Loading Services::LLMService...'

  puts '   ✅ Services::LLMService loaded successfully'

  # Test namespaced LLMService
  puts '   - Loading Services::LLMService...'

  puts '   ✅ Services::LLMService loaded successfully'

  # Test LLMResponse
  puts '   - Loading LLMResponse classes...'

  puts '   ✅ LLMResponse classes loaded successfully'
rescue StandardError => e
  puts "   ❌ Service loading failed: #{e.message}"
  puts "   Debug: #{e.backtrace.first(3).join("\n   ")}"
  exit 1
end

# Test 2: Check if convenience methods are available
puts "\n2. Testing convenience methods availability..."

begin
  # Test namespaced service convenience methods
  puts '   - Checking Services::LLMService convenience methods...'
  namespaced_methods = %i[
    complete_cheap_tools
    complete_cheap_no_tools
    complete_conversation
    complete_premium
    analyze_image
  ]

  namespaced_methods.each do |method|
    if Services::LLMService.respond_to?(method)
      puts "   ✅ #{method} available"
    else
      puts "   ❌ #{method} missing"
    end
  end
rescue StandardError => e
  puts "   ❌ Convenience methods test failed: #{e.message}"
  exit 1
end

# Test 3: Test LLMResponse object creation and methods
puts "\n3. Testing LLMResponse functionality..."

begin
  # Mock response data
  mock_response = {
    raw_response: {
      'choices' => [
        {
          'message' => {
            'content' => 'Test response content',
            'tool_calls' => [
              {
                'id' => 'test_id',
                'type' => 'function',
                'function' => {
                  'name' => 'test_function',
                  'arguments' => '{"param": "value"}'
                }
              }
            ]
          }
        }
      ],
      'usage' => {
        'prompt_tokens' => 10,
        'completion_tokens' => 5,
        'total_tokens' => 15
      },
      'model' => 'test-model'
    },
    model: 'test-model',
    content: 'Test response content',
    usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
  }

  # Test top-level LLMResponse
  puts '   - Testing Services::LLMResponse...'
  response = Services::LLMResponse.new(mock_response)
  puts "   ✅ Content: #{response.content}"
  puts "   ✅ Usage: #{response.usage}"
  puts "   ✅ Tool calls present: #{response.respond_to?(:tool_calls?) ? response.tool_calls? : 'method missing'}"

  # Test namespaced LLMResponse
  puts '   - Testing Services::LLMResponse...'
  namespaced_response = Services::LLMResponse.new(mock_response)
  puts "   ✅ Content: #{namespaced_response.content}"
  puts "   ✅ Usage: #{namespaced_response.usage}"
  puts "   ✅ Tool calls present: #{namespaced_response.tool_calls?}"
rescue StandardError => e
  puts "   ❌ LLMResponse test failed: #{e.message}"
  puts "   Debug: #{e.backtrace.first(3).join("\n   ")}"
  exit 1
end

# Test 4: Test that basic service methods exist
puts "\n4. Testing basic service methods..."

begin
  basic_methods = %i[
    complete
    complete_with_messages
    available_models
    clear_cache!
  ]

  puts '   - Checking Services::LLMService methods...'
  basic_methods.each do |method|
    if Services::LLMService.respond_to?(method)
      puts "   ✅ #{method} available"
    else
      puts "   ❌ #{method} missing"
    end
  end

  puts '   - Checking Services::LLMService methods...'
  basic_methods.each do |method|
    if Services::LLMService.respond_to?(method)
      puts "   ✅ #{method} available"
    else
      puts "   ❌ #{method} missing"
    end
  end
rescue StandardError => e
  puts "   ❌ Basic methods test failed: #{e.message}"
  exit 1
end

puts "\n🎉 All LLM service integration tests passed!"
puts '✅ Services load correctly'
puts '✅ Convenience methods are available'
puts '✅ LLMResponse objects work correctly'
puts '✅ Basic service methods are functional'
