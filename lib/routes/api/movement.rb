# frozen_string_literal: true

require 'json'
# require_relative '../../services/movement_tracking_service' # TODO: Create this service

module Routes
  module Api
    def self.register_movement_routes(app)
      # Log movement state changes (started/stopped moving)
      app.post '/api/v1/gps/movement' do
        content_type :json

        begin
          request_body = request.body.read
          data = JSON.parse(request_body)

          movement_service = Services::MovementTrackingService.new
          result = movement_service.log_movement_change(
            lat: data['lat'].to_f,
            lng: data['lng'].to_f,
            movement_state: data['movement_state'],
            duration: data['duration'],
            daily_distance: data['daily_distance'].to_f,
            total_distance: data['total_distance'].to_f,
            timestamp: data['timestamp'],
            source: data['source'] || 'api'
          )

          if result[:success]
            { status: 'success', message: 'Movement logged successfully' }.to_json
          else
            halt 500, { status: 'error', message: result[:error] }.to_json
          end

        rescue JSON::ParserError
          halt 400, { status: 'error', message: 'Invalid JSON' }.to_json
        rescue StandardError => e
          Services::LoggerService.log_api_call(
            service: 'Movement API',
            endpoint: '/api/v1/gps/movement',
            error: e.message,
            success: false
          )
          halt 500, { status: 'error', message: 'Internal server error' }.to_json
        end
      end

      # Log hourly position updates (for trail tracking)
      app.post '/api/v1/gps/position' do
        content_type :json

        begin
          request_body = request.body.read
          data = JSON.parse(request_body)

          movement_service = Services::MovementTrackingService.new
          result = movement_service.log_position_update(
            lat: data['lat'].to_f,
            lng: data['lng'].to_f,
            address: data['address'],
            movement_state: data['movement_state'],
            daily_distance: data['daily_distance'].to_f,
            total_distance: data['total_distance'].to_f,
            speed: data['speed'].to_f,
            timestamp: data['timestamp'],
            source: data['source'] || 'api'
          )

          if result[:success]
            { status: 'success', message: 'Position logged successfully' }.to_json
          else
            halt 500, { status: 'error', message: result[:error] }.to_json
          end

        rescue JSON::ParserError
          halt 400, { status: 'error', message: 'Invalid JSON' }.to_json
        rescue StandardError => e
          Services::LoggerService.log_api_call(
            service: 'Movement API',
            endpoint: '/api/v1/gps/position',
            error: e.message,
            success: false
          )
          halt 500, { status: 'error', message: 'Internal server error' }.to_json
        end
      end

      # Get daily trails data for the map
      app.get '/api/v1/gps/daily_trails' do
        content_type :json

        begin
          days = params[:days]&.to_i || 7 # Default to last 7 days
          movement_service = Services::MovementTrackingService.new
          trails = movement_service.get_daily_trails(days)

          {
            status: 'success',
            trails: trails,
            total_days: trails.keys.length
          }.to_json

        rescue StandardError => e
          Services::LoggerService.log_api_call(
            service: 'Movement API',
            endpoint: '/api/v1/gps/daily_trails',
            error: e.message,
            success: false
          )
          halt 500, { status: 'error', message: 'Internal server error' }.to_json
        end
      end

      # Get movement statistics
      app.get '/api/v1/gps/movement_stats' do
        content_type :json

        begin
          movement_service = Services::MovementTrackingService.new
          stats = movement_service.get_movement_statistics

          {
            status: 'success',
            stats: stats
          }.to_json

        rescue StandardError => e
          Services::LoggerService.log_api_call(
            service: 'Movement API',
            endpoint: '/api/v1/gps/movement_stats',
            error: e.message,
            success: false
          )
          halt 500, { status: 'error', message: 'Internal server error' }.to_json
        end
      end
    end
  end
end