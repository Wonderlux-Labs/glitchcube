#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify prompt consolidation works correctly
require_relative '../config/environment'

def test_persona_prompt(persona_name)
  puts '=' * 60
  puts "Testing #{persona_name.upcase} persona prompt generation"
  puts '=' * 60

  context = {
    available_tools: ['control_lights', 'play_music', 'display_text'],
    current_location: 'Test Camp',
    temperature: 85,
    time_of_day: 'evening'
  }

  begin
    # Test new composition service
    prompt = Services::Conversation::PromptCompositionService.build_system_prompt(
      persona: persona_name,
      context: context
    )

    puts "✅ Prompt generated successfully for #{persona_name}"
    puts "📏 Length: #{prompt.length} characters"

    # Check for required sections
    required_sections = [
      'CURRENT DATE AND TIME:',
      'AVAILABLE TOOLS AND CAPABILITIES:',
      'CURRENT ENVIRONMENT:',
      'CHARACTER INTEGRITY (CRITICAL):'
    ]

    required_sections.each do |section|
      if prompt.include?(section)
        puts "✅ Contains required section: #{section}"
      else
        puts "❌ Missing required section: #{section}"
      end
    end

    # Check persona-specific content is included
    if persona_name && prompt.downcase.include?(persona_name.downcase)
      puts '✅ Contains persona-specific content'
    elsif persona_name.nil?
      puts '✅ Using default persona content'
    else
      puts '⚠️  May be missing persona-specific content'
    end

    puts "\nFirst 200 characters:"
    puts "#{prompt[0..199]}..."
    puts
  rescue StandardError => e
    puts "❌ Error generating prompt for #{persona_name}: #{e.message}"
    puts e.backtrace.first(5)
  end
end

def test_legacy_compatibility
  puts '=' * 60
  puts 'Testing legacy SystemPromptService compatibility'
  puts '=' * 60

  context = {
    available_tools: ['control_lights', 'play_music'],
    current_location: 'Test Camp'
  }

  begin
    # Test legacy service still works
    service = Services::Conversation::SystemPromptService.new(
      character: 'buddy',
      context: context
    )

    prompt = service.generate
    puts '✅ Legacy SystemPromptService still functional'
    puts "📏 Length: #{prompt.length} characters"
  rescue StandardError => e
    puts "❌ Legacy compatibility broken: #{e.message}"
    puts e.backtrace.first(5)
  end
end

def main
  puts '🧪 PROMPT CONSOLIDATION TEST SUITE'
  puts 'Testing consolidated prompt system...'
  puts

  # Test each persona
  personas = ['buddy', 'jax', 'lomi', 'zorp', nil] # nil tests default
  personas.each { |persona| test_persona_prompt(persona) }

  # Test legacy compatibility
  test_legacy_compatibility

  puts '=' * 60
  puts '✅ Test suite complete!'
  puts '=' * 60
end

main if __FILE__ == $PROGRAM_NAME
