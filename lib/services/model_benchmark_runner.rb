# frozen_string_literal: true

require 'yaml'
require 'benchmark'
# ErrorHandling module now autoloaded via Zeitwerk

module Services
  class ModelBenchmarkRunner
    include ::Modules::ErrorHandling

    MODES = {
      regression: { vcr: :replay_only, api_calls: false },
      evaluation: { vcr: :record_new, api_calls: true }
    }.freeze

    # Default models to test - can be overridden in scenario YAML
    DEFAULT_MODELS = [
      'openai/gpt-4.1-mini',
      'anthropic/claude-sonnet-4',
      'google/gemini-2.5-flash',
      'deepseek/deepseek-chat-v3-0324'
    ].freeze

    # Full set of available models for reference
    ALL_AVAILABLE_MODELS = [
      'openai/gpt-4.1',
      'openai/gpt-4.1-mini',
      'anthropic/claude-sonnet-4',
      'google/gemini-2.5-flash',
      'google/gemini-2.5-pro',
      'deepseek/deepseek-chat-v3-0324',
      'mistralai/mistral-nemo',
      'moonshotai/kimi-k2',
      'qwen/qwen3-coder',
      'z-ai/glm-4.5'
    ].freeze

    def initialize(mode: :regression)
      @mode = MODES[mode]
      @results = []
      configure_vcr if @mode[:vcr]
    end

    def run_scenario(scenario_file, models: nil)
      scenario = load_scenario(scenario_file)

      # Use models from scenario file if specified, otherwise use defaults
      models_to_test = models || scenario[:models] || DEFAULT_MODELS

      models_to_test.each do |model|
        puts "\n🎯 Testing model: #{model}"
        puts '=' * 60

        result = execute_scenario_for_model(scenario, model)
        @results << result

        display_result(result)
      end

      @results
    end

    def run_all_scenarios(models: nil)
      scenario_files = Dir.glob('benchmark_scenarios/*.yaml')

      scenario_files.each do |file|
        puts "\n📋 Running scenario: #{File.basename(file)}"
        run_scenario(file, models: models)
      end

      generate_report
    end

    private

    def load_scenario(file_path)
      YAML.load_file(file_path).deep_symbolize_keys
    rescue StandardError => e
      Services::Logging::SimpleLogger.error('Failed to load scenario', error: e.message)
      raise "Could not load scenario file: #{e.message}"
    end

    def execute_scenario_for_model(scenario, model)
      # Split model for tools vs conversation if testing split mode
      tools_model = model
      conversation_model = model

      # Support testing model splits like "gpt-4-mini|claude-sonnet"
      if model.include?('|')
        tools_model, conversation_model = model.split('|')
      end

      start_time = Time.now
      result = {
        scenario_name: scenario[:scenario_name],
        model: model,
        tools_model: tools_model,
        conversation_model: conversation_model,
        persona: scenario[:persona],
        started_at: start_time,
        turns: [],
        metrics: {},
        assertions_passed: [],
        assertions_failed: []
      }

      # Create conversation module instance
      conversation = ConversationModule.new
      session_id = "benchmark-#{SecureRandom.uuid}"

      scenario[:turns].each_with_index do |turn, index|
        turn_result = execute_turn(
          conversation,
          turn,
          session_id,
          scenario[:persona],
          tools_model,
          conversation_model,
          index
        )

        result[:turns] << turn_result

        # Run assertions
        run_assertions(turn, turn_result, result)
      end

      # Calculate overall metrics
      result[:metrics] = calculate_metrics(result)
      result[:duration_ms] = ((Time.now - start_time) * 1000).round

      result
    end

    def execute_turn(conversation, turn, session_id, persona, tools_model, conversation_model, turn_index)
      context = {
        session_id: session_id,
        persona: persona,
        tools_model: tools_model,
        model: conversation_model,
        tools: build_tools_from_assertions(turn[:assertions])
      }

      start_time = Time.now

      begin
        response = conversation.call(
          message: turn[:user_input],
          context: context
        )

        {
          turn_index: turn_index,
          user_input: turn[:user_input],
          response_text: response[:response],
          tool_calls: response[:tool_calls],
          duration_ms: ((Time.now - start_time) * 1000).round,
          cost: response[:cost],
          tokens: response[:usage],
          success: true
        }
      rescue StandardError => e
        Services::Logging::SimpleLogger.error('Turn execution failed',
                                              error: e.message,
                                              model: conversation_model,
                                              turn: turn_index)

        {
          turn_index: turn_index,
          user_input: turn[:user_input],
          error: e.message,
          duration_ms: ((Time.now - start_time) * 1000).round,
          success: false
        }
      end
    end

    def build_tools_from_assertions(assertions)
      # Extract expected tools from assertions
      tool_assertions = assertions&.find { |a| a[:type] == 'tool_calls' }
      return [] unless tool_assertions

      # Build tool schemas based on expected tools
      tool_assertions[:expected].map do |expected_tool|
        {
          type: 'function',
          function: {
            name: expected_tool[:name],
            description: "Test tool: #{expected_tool[:name]}",
            parameters: {
              type: 'object',
              properties: build_tool_properties(expected_tool[:params]),
              required: expected_tool[:params]&.keys || []
            }
          }
        }
      end
    end

    def build_tool_properties(params)
      return {} unless params

      params.transform_values do |value|
        case value
        when String
          { type: 'string', description: 'Test parameter' }
        when Integer
          { type: 'integer', description: 'Test parameter' }
        when TrueClass, FalseClass
          { type: 'boolean', description: 'Test parameter' }
        else
          { type: 'string', description: 'Test parameter (converted to string)' }
        end
      end
    end

    def run_assertions(turn, turn_result, overall_result)
      return unless turn[:assertions]

      turn[:assertions].each do |assertion|
        case assertion[:type]
        when 'tool_calls'
          check_tool_calls(assertion, turn_result, overall_result)
        when 'latency'
          check_latency(assertion, turn_result, overall_result)
        when 'response_contains'
          check_response_contains(assertion, turn_result, overall_result)
        when 'persona_consistency'
          check_persona_consistency(assertion, turn_result, overall_result)
        end
      end
    end

    def check_tool_calls(assertion, turn_result, overall_result)
      expected_tools = assertion[:expected].map { |t| t[:name] }
      actual_tools = turn_result[:tool_calls]&.map { |t| t['name'] } || []

      if expected_tools.sort == actual_tools.sort
        overall_result[:assertions_passed] << "Tool calls match: #{expected_tools.join(', ')}"
      else
        overall_result[:assertions_failed] << "Tool calls mismatch. Expected: #{expected_tools}, Got: #{actual_tools}"
      end
    end

    def check_latency(assertion, turn_result, overall_result)
      if turn_result[:duration_ms] <= assertion[:max_ms]
        overall_result[:assertions_passed] << "Latency OK: #{turn_result[:duration_ms]}ms <= #{assertion[:max_ms]}ms"
      else
        overall_result[:assertions_failed] << "Latency exceeded: #{turn_result[:duration_ms]}ms > #{assertion[:max_ms]}ms"
      end
    end

    def check_response_contains(assertion, turn_result, overall_result)
      response_text = turn_result[:response_text]&.downcase || ''
      keywords = assertion[:keywords].map(&:downcase)

      found = keywords.select { |k| response_text.include?(k) }

      if found.any?
        overall_result[:assertions_passed] << "Response contains keywords: #{found.join(', ')}"
      else
        overall_result[:assertions_failed] << "Response missing all keywords: #{keywords.join(', ')}"
      end
    end

    def check_persona_consistency(assertion, turn_result, overall_result)
      response_text = turn_result[:response_text]&.downcase || ''

      must_contain = assertion[:must_contain]&.map(&:downcase) || []
      must_not_contain = assertion[:must_not_contain]&.map(&:downcase) || []

      found_good = must_contain.select { |w| response_text.include?(w) }
      found_bad = must_not_contain.select { |w| response_text.include?(w) }

      if found_good.size == must_contain.size && found_bad.empty?
        overall_result[:assertions_passed] << 'Persona consistency maintained'
      else
        failures = []
        failures << "Missing: #{(must_contain - found_good).join(', ')}" if found_good.size < must_contain.size
        failures << "Should not contain: #{found_bad.join(', ')}" if found_bad.any?
        overall_result[:assertions_failed] << "Persona issues: #{failures.join('; ')}"
      end
    end

    def calculate_metrics(result)
      turns = result[:turns]
      successful_turns = turns.select { |t| t[:success] }

      {
        total_turns: turns.size,
        successful_turns: successful_turns.size,
        success_rate: (successful_turns.size.to_f / turns.size * 100).round(2),
        avg_latency_ms: successful_turns.map { |t| t[:duration_ms] }.sum / successful_turns.size.to_f,
        total_cost: successful_turns.map { |t| t[:cost] || 0 }.sum,
        total_tokens: successful_turns.map { |t| t[:tokens]&.[](:total_tokens) || 0 }.sum,
        assertions_passed: result[:assertions_passed].size,
        assertions_failed: result[:assertions_failed].size,
        assertion_pass_rate: calculate_assertion_pass_rate(result)
      }
    end

    def calculate_assertion_pass_rate(result)
      total = result[:assertions_passed].size + result[:assertions_failed].size
      return 100.0 if total.zero?

      (result[:assertions_passed].size.to_f / total * 100).round(2)
    end

    def display_result(result)
      puts "\n📊 Results for #{result[:model]}:"
      puts '-' * 40
      puts "✅ Success Rate: #{result[:metrics][:success_rate]}%"
      puts "⏱️  Avg Latency: #{result[:metrics][:avg_latency_ms].round}ms"
      puts "💰 Total Cost: $#{'%.6f' % result[:metrics][:total_cost]}"
      puts "🎯 Assertions: #{result[:metrics][:assertions_passed]}/#{result[:metrics][:assertions_passed] + result[:metrics][:assertions_failed]} passed"

      return unless result[:assertions_failed].any?

      puts "\n❌ Failed Assertions:"
      result[:assertions_failed].each { |f| puts "  - #{f}" }
    end

    def generate_report
      puts "\n#{'=' * 60}"
      puts '📈 BENCHMARK SUMMARY REPORT'
      puts '=' * 60

      # Group results by model
      models = @results.group_by { |r| r[:model] }

      models.each do |model, results|
        total_success_rate = results.map { |r| r[:metrics][:success_rate] }.sum / results.size
        avg_latency = results.map { |r| r[:metrics][:avg_latency_ms] }.sum / results.size
        total_cost = results.map { |r| r[:metrics][:total_cost] }.sum

        puts "\n#{model}:"
        puts "  Success Rate: #{total_success_rate.round(2)}%"
        puts "  Avg Latency: #{avg_latency.round}ms"
        puts "  Total Cost: $#{'%.6f' % total_cost}"
      end
    end

    def configure_vcr
      # VCR configuration if needed
    end
  end
end
