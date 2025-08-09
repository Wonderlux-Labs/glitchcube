#!/usr/bin/env ruby
# Script to re-record only failing VCR cassettes

require 'fileutils'

# List of failing specs based on the test output
failing_specs = [
  'spec/integration/simple_session_management_spec.rb',
  'spec/integration/conversation_summarizer_spec.rb', 
  'spec/integration/self_healing_integration_spec.rb',
  'spec/app_spec.rb',
  'spec/tools/base_tool_spec.rb',
  'spec/tools/home_assistant_parallel_tool_spec.rb',
  'spec/integration/home_assistant_conversation_spec.rb',
  'spec/services/llm_service_structured_output_spec.rb',
  'spec/integration/conversation_tool_execution_spec.rb',
  'spec/integration/ha_conversation_integration_spec.rb',
  'spec/integration/conversation_continuation_spec.rb'
]

puts "🔄 Re-recording VCR cassettes for failing specs..."
puts "=" * 60

# Set environment to allow recording
ENV['VCR_RECORD'] = 'true'
ENV['CI'] = 'false'

failing_specs.each do |spec_file|
  if File.exist?(spec_file)
    puts "\n📼 Recording cassettes for: #{spec_file}"
    puts "-" * 40
    
    # Run the spec with VCR recording enabled
    cmd = "VCR_RECORD=true bundle exec rspec #{spec_file}"
    system(cmd)
    
    if $?.success?
      puts "✅ Successfully recorded cassettes for #{spec_file}"
    else
      puts "⚠️  Some tests failed in #{spec_file} - cassettes may be partially recorded"
    end
  else
    puts "⚠️  Spec file not found: #{spec_file}"
  end
end

puts "\n" + "=" * 60
puts "🎉 Cassette recording complete!"
puts "\nNow run the tests again to verify:"
puts "  bundle exec rspec"