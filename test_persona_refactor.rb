#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify persona system works after refactoring

require_relative 'config/environment'

puts 'Testing refactored persona system...'
puts '=' * 50

# Test each persona
%w[buddy jax lomi zorp].each do |persona_name|
  puts "\nTesting #{persona_name.capitalize} persona:"

  begin
    # Create persona instance
    persona = Personas::BasePersona.create(persona_name)

    # Test basic properties
    puts "  ✓ Name: #{persona.name}"
    puts "  ✓ Description: #{persona.description}"
    puts "  ✓ Prompt file: #{persona.prompt_file}"
    puts "  ✓ Available tools: #{persona.available_tools.map(&:name).join(', ')}"
    puts "  ✓ Voice style: #{persona.voice_config['style'] || 'default'}"
    puts "  ✓ Traits: #{persona.personality_traits.join(', ')}"

    # Test responses
    fallback = persona.generate_fallback_response
    offline = persona.generate_offline_response
    puts "  ✓ Fallback response: #{fallback[0...50]}..."
    puts "  ✓ Offline response: #{offline[0...50]}..."

    # Test system prompt generation
    system_prompt = persona.generate_system_prompt
    puts "  ✓ System prompt generated (#{system_prompt.length} characters)"

    puts "  ✅ #{persona_name.capitalize} persona working correctly!"
  rescue StandardError => e
    puts "  ❌ Error with #{persona_name}: #{e.message}"
    puts "     #{e.backtrace.first}"
  end
end

puts "\n#{'=' * 50}"
puts 'Persona system refactor test complete!'
