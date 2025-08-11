# frozen_string_literal: true

namespace :benchmark do
  desc 'Run model benchmarks with specified models'
  task :run, [:models] => :environment do |_t, args|
    puts '🚀 GlitchCube Model Benchmark'
    puts '=' * 60

    # Parse models from args or use defaults
    models = args[:models]&.split(',') || Services::ModelBenchmarkRunner::DEFAULT_MODELS

    runner = Services::ModelBenchmarkRunner.new(mode: :evaluation)
    results = runner.run_scenario('benchmark_scenarios/basic_tool_test.yaml', models: models)

    # Display summary
    puts "\n📊 BENCHMARK COMPLETE"
    puts '=' * 60
    results.each do |r|
      puts "#{r[:model]}: #{r[:metrics][:assertion_pass_rate]}% pass rate"
    end
  end

  desc 'Run benchmark in regression mode (using VCR cassettes)'
  task regression: :environment do
    puts '🔄 Running benchmark in regression mode (no API calls)'

    runner = Services::ModelBenchmarkRunner.new(mode: :regression)
    runner.run_all_scenarios
  end

  desc 'Test model splitting (tools vs conversation)'
  task test_split: :environment do
    puts '🔀 Testing model split configuration'

    test_models = [
      'openai/gpt-4.1-mini',
      'anthropic/claude-sonnet-4',
      'openai/gpt-4.1-mini|anthropic/claude-sonnet-4'  # Split mode
    ]

    runner = Services::ModelBenchmarkRunner.new(mode: :evaluation)
    results = runner.run_scenario('benchmark_scenarios/basic_tool_test.yaml', models: test_models)

    # Compare split vs non-split
    single_model = results.find { |r| r[:model] == 'openai/gpt-4.1-mini' }
    split_model = results.find { |r| r[:model].include?('|') }

    if single_model && split_model
      puts "\n📊 Split Model Comparison:"
      puts "Single GPT-4.1-mini: $#{'%.6f' % single_model[:metrics][:total_cost]}"
      puts "Split (GPT+Claude): $#{'%.6f' % split_model[:metrics][:total_cost]}"

      savings = single_model[:metrics][:total_cost] - split_model[:metrics][:total_cost]
      if savings.positive?
        puts "💰 Savings with split: $#{'%.6f' % savings}"
      else
        puts "📈 Split costs more by: $#{'%.6f' % savings.abs}"
      end
    end
  end

  desc 'List available models for benchmarking'
  task models: :environment do
    puts '📋 Available Models for Benchmarking'
    puts '=' * 60
    puts "\nDefault Models:"
    Services::ModelBenchmarkRunner::DEFAULT_MODELS.each { |m| puts "  - #{m}" }

    puts "\nAll Available Models:"
    Services::ModelBenchmarkRunner::ALL_AVAILABLE_MODELS.each { |m| puts "  - #{m}" }

    puts "\nModel Splitting:"
    puts '  Use pipe (|) to split tools and conversation models'
    puts '  Example: openai/gpt-4.1-mini|anthropic/claude-sonnet-4'
  end
end
