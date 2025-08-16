# frozen_string_literal: true

require 'sinatra/base'
require 'json'
require_relative '../../modules/globals'
module Routes
  module Admin
    module Scenarios
      # Predefined test scenarios
      def self.save_comparison
        Services::AdminPages.save_comparison
      end
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
      def self.registered(app)
        # Main scenarios interface
        app.get '/admin/scenarios' do
          @scenarios = SCENARIOS
          # Get available models directly
          @model_categories = Services::AdminPages.get_available_models
          # Flat list for backwards compatibility
          @models = Services::AdminPages.get_flat_model_list
          # Get recent comparisons
          begin
            redis = Redis.new(url: GlitchCube.config.redis_url)
            comparison_ids = redis.lrange('recent_scenario_comparisons', 0, 9)
            @recent_comparisons = []
            comparison_ids.each do |id|
              data = redis.get("scenario_comparison:#{id}")
              next unless data

              comparison = JSON.parse(data)
              @recent_comparisons << {
                id: comparison['id'],
                scenario_id: comparison['scenario_id'],
                scenario_name: SCENARIOS[comparison['scenario_id']]&.dig(:name) || 'Unknown',
                models_count: comparison['results']&.size || 0,
                timestamp: comparison['timestamp']
              }
            end
          rescue Redis::CannotConnectError
            @recent_comparisons = []
          end
          @free_models = ModelPresets::FREE_MODELS
          erb :admin_scenarios
        end
        # Run scenario comparison
        app.post '/admin/scenarios/compare' do
          content_type :json
          begin
            data = JSON.parse(request.body.read)
            scenario_id = data['scenario_id']
            models = data['models'] || []
            persona = data['persona'] || Modules::Globals.persona
            scenario = SCENARIOS[scenario_id]
            return { error: 'Scenario not found' }.to_json unless scenario

            # Run scenario for each model
            results = []
            models.each do |model|
              result = Services::AdminPages.run_scenario_for_model(scenario, model, persona)
              results << result
            end
            # Save comparison for history
            Services::AdminPages.save_comparison(scenario_id, results)
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
            persona = data['persona'] || Modules::Globals.persona
            results = []
            models.each do |model|
              result = Services::AdminPages.run_scenario_for_model(custom_scenario, model, persona)
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
          comparison = Services::AdminPages.load_comparison(params[:comparison_id])
          return 'Comparison not found' unless comparison

          csv_data = Services::AdminPages.generate_comparison_csv(comparison)
          attachment "comparison_#{params[:comparison_id]}.csv"
          csv_data
        end
      end
    end
  end
end
