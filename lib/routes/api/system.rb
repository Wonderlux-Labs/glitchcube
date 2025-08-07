# frozen_string_literal: true

# Simple Sinatra endpoints for system management
# No Grape dependencies - just plain Sinatra routes

module GlitchCube
  module Routes
    module Api
      module System
        def self.registered(app)
          # Health check endpoint
          app.get '/api/v1/system/health' do
            content_type :json

            begin
              # Check Redis
              redis_ok = begin
                redis_url = GlitchCube.config.redis_url || 'redis://localhost:6379'
                redis = Redis.new(url: redis_url)
                redis.ping == 'PONG'
              rescue StandardError
                false
              end

              # Check Sidekiq queues
              queue_sizes = if redis_ok
                              begin
                                require 'sidekiq/api'
                                {
                                  default: Sidekiq::Queue.new('default').size,
                                  critical: Sidekiq::Queue.new('critical').size,
                                  low: Sidekiq::Queue.new('low').size,
                                  total: Sidekiq::Queue.new.size
                                }
                              rescue StandardError => e
                                { error: e.message }
                              end
                            else
                              { error: 'Redis not available' }
                            end

              # Check database
              db_ok = begin
                require_relative '../../../models/memory'
                Memory.connection.active?
              rescue StandardError
                false
              end

              # Check HomeAssistant
              ha_ok = begin
                client = Services::HomeAssistantClient.new
                client.ping
              rescue StandardError
                false
              end

              # Calculate uptime
              start_time = GlitchCube.start_time || Time.now
              uptime_seconds = (Time.now - start_time).to_i

              status = {
                status: redis_ok && db_ok ? 'healthy' : 'degraded',
                timestamp: Time.now.iso8601,
                services: {
                  redis: redis_ok ? 'ok' : 'error',
                  database: db_ok ? 'ok' : 'error',
                  home_assistant: ha_ok ? 'ok' : 'error',
                  sidekiq: redis_ok ? 'ok' : 'error'
                },
                queues: queue_sizes,
                uptime: {
                  seconds: uptime_seconds,
                  human: "#{uptime_seconds / 3600}h #{(uptime_seconds % 3600) / 60}m"
                },
                version: GlitchCube::VERSION || '1.0.0'
              }

              status code: (status[:status] == 'healthy' ? 200 : 503)
              status.to_json
            rescue StandardError => e
              status 500
              {
                status: 'error',
                error: e.message,
                timestamp: Time.now.iso8601
              }.to_json
            end
          end

          # Restart endpoint
          app.post '/api/v1/system/restart' do
            content_type :json

            # Parse JSON body
            begin
              request_body = request.body.read
              params = request_body.empty? ? {} : JSON.parse(request_body)
            rescue JSON::ParserError
              halt 400, { error: 'Invalid JSON' }.to_json
            end

            # Verify auth token
            auth_token = params['auth_token'] || GlitchCube.config.restart_auth_token || 'change-me-in-production'
            expected_token = GlitchCube.config.restart_auth_token || 'change-me-in-production'

            halt 401, { error: 'Unauthorized' }.to_json unless auth_token == expected_token

            level = params['level'] || 'soft'
            reason = params['reason'] || 'api-triggered'

            # Log the restart request
            Services::LoggerService.log_api_call(
              service: 'system',
              endpoint: 'restart',
              level: level,
              reason: reason
            )

            # Execute restart in background to return response first
            Thread.new do
              sleep 1 # Give time for response to be sent

              script_path = File.expand_path('../../../scripts/glitchcube_restart.sh', __dir__)
              if File.exist?(script_path)
                system("bash #{script_path} #{level} '#{reason}'")
              else
                Services::LoggerService.log_error(
                  error: 'Restart script not found',
                  path: script_path
                )
              end
            end

            {
              status: 'restart_initiated',
              level: level,
              reason: reason,
              timestamp: Time.now.iso8601
            }.to_json
          end

          # Clear queues endpoint
          app.post '/api/v1/system/clear_queues' do
            content_type :json

            # Parse JSON body
            begin
              request_body = request.body.read
              params = request_body.empty? ? {} : JSON.parse(request_body)
            rescue JSON::ParserError
              halt 400, { error: 'Invalid JSON' }.to_json
            end

            # Verify auth token
            auth_token = params['auth_token'] || GlitchCube.config.restart_auth_token || 'change-me-in-production'
            expected_token = GlitchCube.config.restart_auth_token || 'change-me-in-production'

            halt 401, { error: 'Unauthorized' }.to_json unless auth_token == expected_token

            begin
              require 'sidekiq/api'

              # Clear all queues
              cleared = {}
              %w[default critical low].each do |queue_name|
                queue = Sidekiq::Queue.new(queue_name)
                size = queue.size
                queue.clear
                cleared[queue_name] = size
              end

              # Clear retry set
              retry_set = Sidekiq::RetrySet.new
              retry_size = retry_set.size
              retry_set.clear
              cleared['retry'] = retry_size

              # Clear dead set
              dead_set = Sidekiq::DeadSet.new
              dead_size = dead_set.size
              dead_set.clear
              cleared['dead'] = dead_size

              Services::LoggerService.log_api_call(
                service: 'system',
                endpoint: 'clear_queues',
                cleared: cleared
              )

              {
                status: 'success',
                cleared: cleared,
                timestamp: Time.now.iso8601
              }.to_json
            rescue StandardError => e
              status 500
              {
                status: 'error',
                error: e.message,
                timestamp: Time.now.iso8601
              }.to_json
            end
          end

          # Restart history endpoint
          app.get '/api/v1/system/restart_history' do
            content_type :json

            # Read from log file if available
            log_file = GlitchCube.config.restart_log_file || '/tmp/glitchcube_restart.log'

            history = []
            if File.exist?(log_file)
              File.readlines(log_file).reverse.take(20).each do |line|
                next unless (match = line.match(/\[(.*?)\] (.*?) restart: (.*)/))

                history << {
                  timestamp: match[1],
                  level: match[2],
                  reason: match[3].strip
                }
              end
            end

            # Calculate stats
            now = Time.now
            count_24h = history.count do |h|
              Time.parse(h[:timestamp]) > (now - 86_400)
            rescue StandardError
              false
            end

            count_7d = history.count do |h|
              Time.parse(h[:timestamp]) > (now - 604_800)
            rescue StandardError
              false
            end

            {
              history: history.take(10),
              count_24h: count_24h,
              count_7d: count_7d,
              timestamp: now.iso8601
            }.to_json
          end
        end
      end
    end
  end
end
