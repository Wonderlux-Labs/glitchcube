# frozen_string_literal: true

require 'sinatra/base'
require 'json'
require 'fileutils'

module GlitchCube
  module Routes
    module AdminBenchmarks
      def self.registered(app)
        # Main benchmark page
        app.get '/admin/benchmarks' do
          # Ensure benchmark_scenarios directory exists
          scenarios_dir = 'benchmark_scenarios'
          FileUtils.mkdir_p(scenarios_dir) unless File.directory?(scenarios_dir)

          @scenarios = Dir.glob("#{scenarios_dir}/*.yaml").map do |file|
            scenario = YAML.load_file(file).deep_symbolize_keys
            scenario[:filename] = File.basename(file)
            scenario
          end

          @default_models = Services::ModelBenchmarkRunner::DEFAULT_MODELS
          @all_models = Services::ModelBenchmarkRunner::ALL_AVAILABLE_MODELS

          # Load any existing results inline
          begin
            results_dir = 'benchmark_results'
            FileUtils.mkdir_p(results_dir) unless File.directory?(results_dir)

            result_files = Dir.glob("#{results_dir}/*.json")
                              .sort_by { |f| File.mtime(f) }
                              .reverse
                              .first(10)

            @recent_results = if result_files.empty?
                                []
                              else
                                result_files.map do |file|
                                  data = JSON.parse(File.read(file), symbolize_names: true)
                                  {
                                    filename: File.basename(file),
                                    timestamp: File.mtime(file),
                                    data: data
                                  }
                                end
                              end
          rescue StandardError => e
            @recent_results = []
          end

          erb :admin_benchmarks
        end

        # Run benchmark via AJAX
        app.post '/admin/benchmarks/run' do
          content_type :json

          scenario_file = params[:scenario]
          models = params[:models]&.split(',')&.map(&:strip) || Services::ModelBenchmarkRunner::DEFAULT_MODELS
          mode = params[:mode] || 'evaluation'

          begin
            runner = Services::ModelBenchmarkRunner.new(mode: mode.to_sym)
            results = runner.run_scenario("benchmark_scenarios/#{scenario_file}", models: models)

            # Save results
            save_results(results, scenario_file)

            {
              success: true,
              results: format_results_for_display(results),
              summary: generate_summary(results)
            }.to_json
          rescue StandardError => e
            Services::Logging::SimpleLogger.error('Benchmark failed', error: e.message)
            {
              success: false,
              error: e.message
            }.to_json
          end
        end

        # Get benchmark history
        app.get '/admin/benchmarks/history' do
          content_type :json

          results = load_all_results
          results.to_json
        end

        # Compare specific models
        app.post '/admin/benchmarks/compare' do
          content_type :json

          models = params[:models]&.split(',')&.map(&:strip)
          return { error: 'Please select at least 2 models to compare' }.to_json if models.nil? || models.size < 2

          begin
            # Run all scenarios for comparison
            runner = Services::ModelBenchmarkRunner.new(mode: :evaluation)
            all_results = []

            Dir.glob('benchmark_scenarios/*.yaml').each do |file|
              results = runner.run_scenario(file, models: models)
              all_results.concat(results)
            end

            comparison = generate_comparison(all_results, models)

            {
              success: true,
              comparison: comparison
            }.to_json
          rescue StandardError => e
            {
              success: false,
              error: e.message
            }.to_json
          end
        end
      end

      private

      def self.load_recent_results(limit = 10)
        # Ensure the results directory exists
        results_dir = 'benchmark_results'
        FileUtils.mkdir_p(results_dir) unless File.directory?(results_dir)

        result_files = Dir.glob("#{results_dir}/*.json")
                          .sort_by { |f| File.mtime(f) }
                          .reverse
                          .first(limit)

        return [] if result_files.empty?

        result_files.map do |file|
          data = JSON.parse(File.read(file), symbolize_names: true)
          {
            filename: File.basename(file),
            timestamp: File.mtime(file),
            data: data
          }
        end
      rescue StandardError => e
        Services::Logging::SimpleLogger.error('Failed to load results', error: e.message) if defined?(Services::Logging::SimpleLogger)
        []
      end

      def self.load_all_results
        Dir.glob('benchmark_results/*.json').map do |file|
          JSON.parse(File.read(file), symbolize_names: true)
        end.flatten
      rescue StandardError => e
        []
      end

      def self.save_results(results, scenario_file)
        timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
        scenario_name = File.basename(scenario_file, '.yaml')

        FileUtils.mkdir_p('benchmark_results')

        filename = "benchmark_results/#{scenario_name}_#{timestamp}.json"
        File.write(filename, JSON.pretty_generate(results))

        filename
      rescue StandardError => e
        Services::Logging::SimpleLogger.error('Failed to save results', error: e.message)
        nil
      end

      def self.format_results_for_display(results)
        results.map do |result|
          {
            model: result[:model],
            tools_model: result[:tools_model],
            conversation_model: result[:conversation_model],
            success_rate: result[:metrics][:success_rate],
            avg_latency: result[:metrics][:avg_latency_ms]&.round,
            total_cost: result[:metrics][:total_cost],
            assertions_passed: result[:metrics][:assertions_passed],
            assertions_failed: result[:metrics][:assertions_failed],
            assertion_pass_rate: result[:metrics][:assertion_pass_rate],
            turns: result[:turns].map do |t|
              {
                user_input: t[:user_input],
                response: t[:response_text],
                tool_calls: t[:tool_calls],
                duration_ms: t[:duration_ms],
                success: t[:success]
              }
            end
          }
        end
      end

      def self.generate_summary(results)
        best_performance = results.max_by { |r| r[:metrics][:assertion_pass_rate] }
        fastest = results.min_by { |r| r[:metrics][:avg_latency_ms] || Float::INFINITY }
        cheapest = results.min_by { |r| r[:metrics][:total_cost] || Float::INFINITY }

        {
          best_overall: best_performance[:model],
          best_score: best_performance[:metrics][:assertion_pass_rate],
          fastest_model: fastest[:model],
          fastest_time: fastest[:metrics][:avg_latency_ms]&.round,
          cheapest_model: cheapest[:model],
          cheapest_cost: cheapest[:metrics][:total_cost]
        }
      end

      def self.generate_comparison(results, models)
        comparison = {}

        models.each do |model|
          model_results = results.select { |r| r[:model] == model }

          comparison[model] = {
            scenarios_run: model_results.size,
            avg_success_rate: model_results.map { |r| r[:metrics][:success_rate] }.sum / model_results.size.to_f,
            avg_latency: model_results.map { |r| r[:metrics][:avg_latency_ms] || 0 }.sum / model_results.size.to_f,
            total_cost: model_results.map { |r| r[:metrics][:total_cost] || 0 }.sum,
            avg_assertion_rate: model_results.map { |r| r[:metrics][:assertion_pass_rate] }.sum / model_results.size.to_f
          }
        end

        comparison
      end
    end
  end
end
