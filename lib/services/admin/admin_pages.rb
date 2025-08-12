# frozen_string_literal: true

module Services
  class AdminPages
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

          get_available_models = lambda do
            {
              'Free Models (Recommended for Testing)' => GlitchCube::ModelPresets::FREE_MODELS,
              'Cheap Models with Tools' => GlitchCube::ModelPresets::CHEAP_TOOLS_MODELS,
              'Conversation Models' => GlitchCube::ModelPresets::CONVERSATION_MODELS,
              'Vision Models' => GlitchCube::ModelPresets::VISION_MODELS,
              'Premium Models (Higher Cost)' => GlitchCube::ModelPresets::PREMIUM_MODELS
            }
          end

          get_flat_model_list = lambda do
            get_available_models.call.values.flatten.uniq.reject { |model| GlitchCube::ModelPresets.blacklisted?(model) }
          end
        end
      end
    end
  end
end
