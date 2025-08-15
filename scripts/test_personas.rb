#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../app'

# Test each persona
personas = %w[buddy jax lomi zorp]

personas.each do |persona_name|
  puts "\n=== Testing #{persona_name.capitalize} Persona ==="
  begin
    persona = Personas::BasePersona.create(persona_name)
    puts "✓ Created #{persona_name} successfully"
    puts "  Name: #{persona.name}"

    # Test available_tools method
    tools = persona.available_tools
    puts "  Available tools: #{tools.inspect}"

    # Test tool_schemas method
    schemas = persona.tool_schemas
    puts "  Tool schemas count: #{schemas.length}"

    if schemas.any?
      puts '  Tool functions:'
      schemas.each do |schema|
        func_name = schema.dig('function', 'name')
        func_desc = schema.dig('function', 'description').to_s[0..60]
        puts "    - #{func_name}: #{func_desc}..."
      end
    end
  rescue StandardError => e
    puts "✗ Error with #{persona_name}: #{e.class} - #{e.message}"
    puts "  Backtrace: #{e.backtrace.first(3).join("\n  ")}"
  end
end

puts "\n=== Tool Class Loading Test ==="
[Tools::LightingTool, Tools::HassMcpTool].each do |tool_class|
  puts "\nTesting #{tool_class}:"
  puts "  Available tools: #{tool_class.available_tools}"
  puts "  Tool schemas: #{tool_class.tool_schemas.keys}"
end

puts "\n=== Registry Check ==="
puts "Registered personas: #{Personas::BasePersona.available_personas}"
