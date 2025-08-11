#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../config/environment'

puts '🚀 GlitchCube Model Benchmark Runner'
puts '=' * 60

# Parse command line arguments
mode = ARGV[0] || 'regression'
scenario_file = ARGV[1] || 'benchmark_scenarios/basic_tool_test.yaml'
models = ARGV[2]&.split(',')

puts "Mode: #{mode}"
puts "Scenario: #{scenario_file}"
puts "Models: #{models || 'Using defaults'}"
puts

# Create benchmark runner
runner = Services::ModelBenchmarkRunner.new(mode: mode.to_sym)

# Run the benchmark
if scenario_file == 'all'
  puts 'Running all scenarios...'
  runner.run_all_scenarios(models: models)
else
  puts 'Running single scenario...'
  results = runner.run_scenario(scenario_file, models: models)

  # Save results to JSON for later analysis
  timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
  output_file = "benchmark_results/results_#{timestamp}.json"

  FileUtils.mkdir_p('benchmark_results')
  File.write(output_file, JSON.pretty_generate(results))

  puts "\n✅ Results saved to: #{output_file}"
end

puts "\n🎉 Benchmark complete!"
