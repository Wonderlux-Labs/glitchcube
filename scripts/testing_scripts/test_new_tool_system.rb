#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify the new method-based tool system

puts '🧪 Testing new method-based tool system...'
puts '=' * 50

begin
  # Test: Discover tools
  puts "\n1. Discovering tools..."
  tools = Services::ToolRegistryService.discover_tools
  puts "   Found #{tools.size} tools: #{tools.keys.join(', ')}"

  # Test: Generate schemas for method-based tools
  puts "\n2. Testing method-based schema generation..."

  # Test specifically with lighting_control
  puts "\n   Testing LightingTool methods:"
  lighting_functions = Services::ToolRegistryService.get_tool_methods_as_functions(['lighting_control'])
  puts "   Found #{lighting_functions.size} lighting functions"
  lighting_functions.each do |func|
    puts "   ✅ #{func[:function][:name]}: #{func[:function][:description]}"
    puts "      Required: #{func[:function][:parameters][:required].join(', ')}"
    puts "      Properties: #{func[:function][:parameters][:properties].keys.join(', ')}"
  end

  # Test: Generate schemas for music_control
  puts "\n   Testing MusicTool methods:"
  music_functions = Services::ToolRegistryService.get_tool_methods_as_functions(['music_control'])
  puts "   Found #{music_functions.size} music functions"
  music_functions.each do |func|
    puts "   ✅ #{func[:function][:name]}: #{func[:function][:description]}"
    puts "      Required: #{func[:function][:parameters][:required].join(', ')}"
    puts "      Properties: #{func[:function][:parameters][:properties].keys.join(', ')}"
  end

  puts "\n✅ Method-based tool system working correctly!"
rescue StandardError => e
  puts "\n❌ Error testing tool system:"
  puts "   #{e.class}: #{e.message}"
  puts "   #{e.backtrace.first(3).join("\n   ")}" if e.backtrace
end

puts "\n#{'=' * 50}"
puts '🎯 Test complete!'
