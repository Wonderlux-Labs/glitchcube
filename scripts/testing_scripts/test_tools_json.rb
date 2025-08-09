#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative 'config/environment'
require_relative 'lib/services/tool_registry_service'

puts 'Testing Tool JSON Responses...'
puts '=' * 50

# Test 1: Tool Discovery
puts "\n1. Testing Tool Discovery..."
begin
  tools = Services::ToolRegistryService.discover_tools
  json_str = { success: true, tools: tools.keys }.to_json
  parsed = JSON.parse(json_str)
  puts "✅ Tool discovery returns valid JSON with #{parsed['tools'].size} tools"
rescue StandardError => e
  puts "❌ Tool discovery failed: #{e.message}"
end

# Test 2: Tool Formatting
puts "\n2. Testing Tool Formatting..."
begin
  tools = Services::ToolRegistryService.discover_tools
  formatted_tools = tools.map do |name, info|
    {
      name: name,
      display_name: name.split('_').map(&:capitalize).join(' '),
      description: info[:description],
      category: info[:category],
      parameters: info[:parameters],
      examples: info[:examples] || [],
      class_name: info[:class_name]
    }
  end

  json_str = { success: true, tools: formatted_tools }.to_json
  parsed = JSON.parse(json_str)
  puts '✅ Formatted tools returns valid JSON'

  # Check each tool has required fields
  parsed['tools'].each do |tool|
    missing = []
    missing << 'name' unless tool['name']
    missing << 'description' unless tool['description']
    missing << 'parameters' unless tool['parameters']

    puts "  ⚠️  Tool '#{tool['name']}' missing fields: #{missing.join(', ')}" if missing.any?
  end
rescue StandardError => e
  puts "❌ Tool formatting failed: #{e.message}"
end

# Test 3: OpenAI Function Specs
puts "\n3. Testing OpenAI Function Specs..."
begin
  functions = Services::ToolRegistryService.get_openai_functions
  json_str = { success: true, functions: functions }.to_json
  parsed = JSON.parse(json_str)
  puts "✅ OpenAI functions returns valid JSON with #{parsed['functions'].size} functions"
rescue StandardError => e
  puts "❌ OpenAI functions failed: #{e.message}"
end

# Test 4: Character-specific Tools
puts "\n4. Testing Character-specific Tools..."
%w[buddy jax lomi].each do |character|
  functions = Services::ToolRegistryService.get_tools_for_character(character)
  json_str = { success: true, character: character, functions: functions }.to_json
  parsed = JSON.parse(json_str)
  puts "✅ #{character.capitalize} tools returns valid JSON with #{parsed['functions'].size} functions"
rescue StandardError => e
  puts "❌ #{character.capitalize} tools failed: #{e.message}"
end

# Test 5: Error Handling
puts "\n5. Testing Error Handling..."
begin
  # Try to execute a non-existent tool
  result = Services::ToolRegistryService.execute_tool_directly('nonexistent_tool', {})
  json_str = result.to_json
  parsed = JSON.parse(json_str)
  if parsed['success'] == false
    puts '✅ Non-existent tool returns valid error JSON'
  else
    puts "⚠️  Non-existent tool didn't return expected error"
  end
rescue StandardError => e
  puts "❌ Error handling test failed: #{e.message}"
end

# Test 6: Tool Execution
puts "\n6. Testing Tool Execution..."
begin
  result = Services::ToolRegistryService.execute_tool_directly('test_tool', { action: 'simple_test' })
  json_str = result.to_json
  parsed = JSON.parse(json_str)
  puts "✅ Tool execution returns valid JSON: success=#{parsed['success']}"
rescue StandardError => e
  puts "❌ Tool execution failed: #{e.message}"
end

puts "\n#{'=' * 50}"
puts 'JSON Testing Complete!'
