#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../config/environment'

puts '🧪 Quick Benchmark Test'
puts '=' * 60
puts

# Test with just 2 models for speed
test_models = [
  'openai/gpt-4.1-mini',
  'anthropic/claude-sonnet-4'
]

# Also test model splitting
if ENV['TEST_SPLIT'] == 'true'
  test_models << 'openai/gpt-4.1-mini|anthropic/claude-sonnet-4'
  puts 'Including model split test!'
end

runner = Services::ModelBenchmarkRunner.new(mode: :evaluation)

begin
  results = runner.run_scenario(
    'benchmark_scenarios/basic_tool_test.yaml',
    models: test_models
  )

  puts "\n#{'=' * 60}"
  puts '📊 FINAL COMPARISON'
  puts '=' * 60

  results.each do |result|
    puts "\n#{result[:model]}:"
    puts "  ✅ Success: #{result[:metrics][:success_rate]}%"
    puts "  ⏱️  Latency: #{result[:metrics][:avg_latency_ms].round}ms"
    puts "  💰 Cost: $#{'%.6f' % result[:metrics][:total_cost]}"
    puts "  🎯 Score: #{result[:metrics][:assertion_pass_rate]}%"
  end

  # Find the winner
  winner = results.max_by { |r| r[:metrics][:assertion_pass_rate] }
  puts "\n🏆 Best Performance: #{winner[:model]} (#{winner[:metrics][:assertion_pass_rate]}% assertions passed)"
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end
