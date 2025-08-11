# frozen_string_literal: true

require 'sinatra/base'
require 'json'

module GlitchCube
  module Routes
    module AdminScenarios
      # Predefined test scenarios
      SCENARIOS = {
        'first_contact' => {
          name: 'First Contact',
          category: 'basic',
          description: 'Initial interaction with the cube',
          messages: [
            { role: 'user', content: 'Hello! What are you?' },
            { role: 'user', content: 'Can you tell me more about yourself?' }
          ]
        },
        'ride_request' => {
          name: 'Ride Request',
          category: 'navigation',
          description: 'User needs transportation',
          messages: [
            { role: 'user', content: 'I need to get to 6:30 and Esplanade, can you help?' },
            { role: 'user', content: 'How long will it take to get there?' }
          ]
        },
        'party_mode' => {
          name: 'Party Mode',
          category: 'entertainment',
          description: 'Activate party features',
          messages: [
            { role: 'user', content: "Let's have a dance party!" },
            { role: 'user', content: 'Turn up the music and lights!' }
          ]
        },
        'hardware_demo' => {
          name: 'Hardware Demo',
          category: 'technical',
          description: 'Demonstrate all hardware capabilities',
          messages: [
            { role: 'user', content: 'Show me everything you can do with your hardware' },
            { role: 'user', content: 'Can you use all your tools at once?' }
          ]
        },
        'persona_test' => {
          name: 'Persona Test',
          category: 'personality',
          description: 'Test different persona responses',
          messages: [
            { role: 'user', content: 'Tell me a joke' },
            { role: 'user', content: 'What makes you unique?' }
          ]
        },
        'error_handling' => {
          name: 'Error Handling',
          category: 'edge_cases',
          description: 'Test error scenarios',
          messages: [
            { role: 'user', content: 'Execute undefined_tool with parameters' },
            { role: 'user', content: 'What happens if Home Assistant is down?' }
          ]
        },
        'memory_test' => {
          name: 'Memory Test',
          category: 'memory',
          description: 'Test memory and context',
          messages: [
            { role: 'user', content: 'My name is TestUser and I love electronic music' },
            { role: 'user', content: "What's my name and what do I like?" }
          ]
        },
        'location_aware' => {
          name: 'Location Awareness',
          category: 'gps',
          description: 'Test location-based responses',
          messages: [
            { role: 'user', content: 'Where are we right now?' },
            { role: 'user', content: "What's nearby?" }
          ]
        }
      }.freeze

      # Get available models from config - organized by category for testing
      def self.get_available_models
        {
          'Free Models (Recommended for Testing)' => GlitchCube::ModelPresets::FREE_MODELS,
          'Cheap Models with Tools' => GlitchCube::ModelPresets::CHEAP_TOOLS_MODELS,
          'Conversation Models' => GlitchCube::ModelPresets::CONVERSATION_MODELS,
          'Vision Models' => GlitchCube::ModelPresets::VISION_MODELS,
          'Premium Models (Higher Cost)' => GlitchCube::ModelPresets::PREMIUM_MODELS
        }
      end

      # Flat list of all available models for backwards compatibility
      def self.get_flat_model_list
        get_available_models.values.flatten.uniq.reject { |model| GlitchCube::ModelPresets.blacklisted?(model) }
      end

      def self.registered(app)
        # Main scenarios interface
        app.get '/admin/scenarios' do
          @scenarios = SCENARIOS
          @model_categories = get_available_models
          @models = get_flat_model_list # For backwards compatibility
          @recent_comparisons = get_recent_comparisons
          erb :admin_scenarios
        end

        # Run scenario comparison
        app.post '/admin/scenarios/compare' do
          content_type :json

          begin
            data = JSON.parse(request.body.read)
            scenario_id = data['scenario_id']
            models = data['models'] || []
            persona = data['persona'] || 'buddy'

            scenario = SCENARIOS[scenario_id]
            return { error: 'Scenario not found' }.to_json unless scenario

            # Run scenario for each model
            results = []

            models.each do |model|
              result = run_scenario_for_model(scenario, model, persona)
              results << result
            end

            # Save comparison for history
            save_comparison(scenario_id, results)

            {
              success: true,
              scenario: scenario,
              results: results,
              comparison_id: SecureRandom.hex(8),
              timestamp: Time.now.iso8601
            }.to_json
          rescue StandardError => e
            status 500
            { error: e.message, backtrace: e.backtrace.first(5) }.to_json
          end
        end

        # Get scenario details
        app.get '/admin/scenarios/:id' do
          content_type :json

          scenario = SCENARIOS[params[:id]]
          return { error: 'Scenario not found' }.to_json unless scenario

          scenario.to_json
        end

        # Create custom scenario
        app.post '/admin/scenarios/custom' do
          content_type :json

          begin
            data = JSON.parse(request.body.read)

            custom_scenario = {
              name: data['name'] || 'Custom Scenario',
              category: 'custom',
              description: data['description'] || 'User-defined scenario',
              messages: data['messages'] || []
            }

            # Run the custom scenario
            models = data['models'] || ['google/gemini-2.0-flash-exp:free']
            persona = data['persona'] || 'buddy'

            results = []
            models.each do |model|
              result = run_scenario_for_model(custom_scenario, model, persona)
              results << result
            end

            {
              success: true,
              scenario: custom_scenario,
              results: results,
              timestamp: Time.now.iso8601
            }.to_json
          rescue StandardError => e
            status 500
            { error: e.message }.to_json
          end
        end

        # Export comparison results
        app.get '/admin/scenarios/export/:comparison_id' do
          content_type 'text/csv'

          comparison = load_comparison(params[:comparison_id])
          return 'Comparison not found' unless comparison

          csv_data = generate_comparison_csv(comparison)

          attachment "comparison_#{params[:comparison_id]}.csv"
          csv_data
        end
      end

      private

      def self.run_scenario_for_model(scenario, model, persona)
        # Validate model against blacklist
        if GlitchCube::ModelPresets.blacklisted?(model)
          return {
            model: model,
            persona: persona,
            session_id: 'blocked',
            responses: [],
            metrics: { total_cost: 0, total_tokens: 0, execution_time_ms: 0, errors_count: 1 },
            errors: [{ error: "Model #{model} is blacklisted due to high cost", phase: 'validation' }],
            timestamp: Time.now.iso8601
          }
        end

        start_time = Time.now
        session_id = "scenario_#{SecureRandom.hex(8)}"

        # Track metrics
        total_cost = 0
        total_tokens = 0
        tool_calls = []
        responses = []
        errors = []

        begin
          # Create conversation session
          conversation_module = ConversationModule.new

          # Process each message in scenario
          scenario[:messages].each_with_index do |message, idx|
            # Prepare request
            request_data = {
              'message' => message[:content],
              'session_id' => session_id,
              'persona' => persona,
              'model_override' => model,
              'source' => 'scenario_test'
            }

            # Process conversation
            result = conversation_module.process_conversation(
              message: request_data['message'],
              session_id: session_id,
              persona: persona.to_sym,
              context: { model_override: model }
            )

            # Extract metrics
            if result[:usage]
              total_tokens += result[:usage][:total_tokens] || 0
              total_cost += result[:usage][:total_cost] || 0
            end

            # Track tool usage
            if result[:tool_calls]
              tool_calls.concat(result[:tool_calls])
            end

            responses << {
              message_index: idx,
              user_message: message[:content],
              response: result[:response],
              tokens: result[:usage]&.dig(:total_tokens) || 0,
              cost: result[:usage]&.dig(:total_cost) || 0,
              tools_used: result[:tool_calls]&.map { |t| t[:name] } || []
            }
          rescue StandardError => e
            errors << {
              message_index: idx,
              error: e.message
            }
            responses << {
              message_index: idx,
              user_message: message[:content],
              response: "Error: #{e.message}",
              error: true
            }
          end
        rescue StandardError => e
          errors << { error: e.message, phase: 'initialization' }
        end

        execution_time = ((Time.now - start_time) * 1000).round

        {
          model: model,
          persona: persona,
          session_id: session_id,
          responses: responses,
          metrics: {
            total_cost: total_cost.round(6),
            total_tokens: total_tokens,
            execution_time_ms: execution_time,
            avg_response_time_ms: responses.empty? ? 0 : (execution_time / responses.size).round,
            tool_calls_count: tool_calls.size,
            unique_tools_used: tool_calls.map { |t| t[:name] }.uniq,
            errors_count: errors.size
          },
          errors: errors,
          timestamp: Time.now.iso8601
        }
      end

      def self.save_comparison(scenario_id, results)
        # Store in Redis for quick access
        redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0')
        comparison_id = SecureRandom.hex(8)

        comparison_data = {
          id: comparison_id,
          scenario_id: scenario_id,
          results: results,
          timestamp: Time.now.iso8601
        }

        redis.setex(
          "scenario_comparison:#{comparison_id}",
          3600, # Expire after 1 hour
          comparison_data.to_json
        )

        # Also append to recent comparisons list
        redis.lpush('recent_scenario_comparisons', comparison_id)
        redis.ltrim('recent_scenario_comparisons', 0, 19) # Keep last 20

        comparison_id
      rescue Redis::CannotConnectError
        # Fallback to file storage if Redis unavailable
        nil
      end

      def self.get_recent_comparisons
        redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0')
        comparison_ids = redis.lrange('recent_scenario_comparisons', 0, 9)

        comparisons = []
        comparison_ids.each do |id|
          data = redis.get("scenario_comparison:#{id}")
          next unless data

          comparison = JSON.parse(data)
          comparisons << {
            id: comparison['id'],
            scenario_id: comparison['scenario_id'],
            scenario_name: SCENARIOS[comparison['scenario_id']]&.dig(:name) || 'Unknown',
            models_count: comparison['results']&.size || 0,
            timestamp: comparison['timestamp']
          }
        end

        comparisons
      rescue Redis::CannotConnectError
        []
      end

      def self.load_comparison(comparison_id)
        redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0')
        data = redis.get("scenario_comparison:#{comparison_id}")
        return nil unless data

        JSON.parse(data)
      rescue Redis::CannotConnectError
        nil
      end

      def self.generate_comparison_csv(comparison)
        require 'csv'

        CSV.generate do |csv|
          # Headers
          csv << ['Model', 'Persona', 'Message Index', 'User Message', 'Response', 'Tokens', 'Cost', 'Tools Used', 'Response Time (ms)']

          # Data rows
          comparison['results'].each do |result|
            model = result['model']
            persona = result['persona']

            result['responses'].each do |response|
              csv << [
                model,
                persona,
                response['message_index'],
                response['user_message'],
                response['response'],
                response['tokens'],
                response['cost'],
                (response['tools_used'] || []).join(', '),
                result['metrics']['avg_response_time_ms']
              ]
            end
          end
        end
      end
    end
  end
end
