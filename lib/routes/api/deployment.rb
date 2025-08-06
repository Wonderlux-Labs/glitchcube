# frozen_string_literal: true

require 'json'
require 'openssl'
require 'digest'

module GlitchCube
  module Routes
    module Api
      # GitHub webhook handler for automated deployment
      module Deployment
        def self.registered(app)
          # GitHub webhook endpoint for deployment automation
          app.post '/api/v1/deploy/webhook' do
            content_type :json
            
            begin
              # Read the raw payload
              request.body.rewind
              payload_body = request.body.read
              
              # Validate GitHub webhook signature if secret is configured
              if GlitchCube.config.deployment&.github_webhook_secret
                validate_github_signature!(request, payload_body)
              end
              
              # Parse the payload
              payload = JSON.parse(payload_body)
              
              # Only handle push events to main branch
              if payload['ref'] != 'refs/heads/main'
                return json({ 
                  message: 'Ignoring non-main branch push',
                  ref: payload['ref'],
                  skipped: true
                })
              end
              
              # Extract commit information
              commits = payload['commits'] || []
              latest_commit = commits.last
              
              deployment_info = {
                repository: payload.dig('repository', 'full_name'),
                branch: payload['ref']&.gsub('refs/heads/', ''),
                commit_sha: payload['after'],
                commit_message: latest_commit&.dig('message'),
                committer: latest_commit&.dig('committer', 'name'),
                timestamp: Time.now.iso8601
              }
              
              # Log the deployment request
              Services::LoggerService.log_api_call(
                service: 'github_webhook',
                endpoint: '/deploy/webhook',
                method: 'POST',
                deployment_info: deployment_info
              )
              
              # Execute deployment in background
              deployment_result = execute_deployment(deployment_info)
              
              json({
                message: 'Deployment initiated successfully',
                deployment: deployment_info,
                result: deployment_result,
                webhook_processed: true
              })
              
            rescue SecurityError => e
              status 401
              json({ 
                error: 'Webhook signature validation failed', 
                message: e.message,
                webhook_processed: false
              })
              
            rescue JSON::ParserError => e
              status 400
              json({ 
                error: 'Invalid JSON payload', 
                message: e.message,
                webhook_processed: false
              })
              
            rescue StandardError => e
              status 500
              Services::LoggerService.log_api_call(
                service: 'github_webhook',
                endpoint: '/deploy/webhook',
                method: 'POST',
                status: 500,
                error: e.message,
                backtrace: e.backtrace.first(3)
              )
              
              json({ 
                error: 'Deployment failed', 
                message: e.message,
                webhook_processed: false
              })
            end
          end
          
          # Internal deployment endpoint (called by Home Assistant)
          app.post '/api/v1/deploy/internal' do
            content_type :json
            
            begin
              # Read the JSON payload
              request.body.rewind
              payload = JSON.parse(request.body.read)
              
              # Only accept requests from Home Assistant (local network)
              client_ip = request.env['HTTP_X_FORWARDED_FOR']&.split(',')&.first&.strip || request.ip
              unless is_home_assistant_ip?(client_ip)
                status 401
                return json({ error: 'Access denied - requests only accepted from Home Assistant' })
              end
              
              deployment_info = {
                repository: payload['repository'] || 'unknown',
                branch: payload['branch'] || 'main',
                commit_sha: payload['commit_sha'] || 'unknown',
                commit_message: payload['commit_message'] || 'Internal deployment',
                committer: payload['committer'] || 'Home Assistant',
                timestamp: payload['timestamp'] || Time.now.iso8601,
                triggered_by: 'home_assistant'
              }
              
              # Log the internal deployment request
              Services::LoggerService.log_api_call(
                service: 'internal_deployment',
                endpoint: '/deploy/internal',
                method: 'POST',
                deployment_info: deployment_info
              )
              
              # Execute deployment
              deployment_result = execute_deployment(deployment_info)
              
              json({
                message: 'Internal deployment completed',
                deployment: deployment_info,
                result: deployment_result,
                success: deployment_result.all? { |r| r[:success] }
              })
              
            rescue JSON::ParserError => e
              status 400
              json({ 
                error: 'Invalid JSON payload', 
                message: e.message 
              })
              
            rescue StandardError => e
              status 500
              Services::LoggerService.log_api_call(
                service: 'internal_deployment',
                endpoint: '/deploy/internal',
                method: 'POST',
                status: 500,
                error: e.message
              )
              
              json({ 
                error: 'Internal deployment failed', 
                message: e.message 
              })
            end
          end
          
          # Manual deployment endpoint (authenticated)
          app.post '/api/v1/deploy/manual' do
            content_type :json
            
            # Simple authentication check
            api_key = request.env['HTTP_X_API_KEY'] || params['api_key']
            unless api_key == GlitchCube.config.deployment&.api_key
              status 401
              return json({ error: 'Invalid API key' })
            end
            
            begin
              deployment_info = {
                repository: 'manual deployment',
                branch: params['branch'] || 'main',
                commit_sha: 'manual',
                commit_message: params['message'] || 'Manual deployment',
                committer: params['committer'] || 'manual',
                timestamp: Time.now.iso8601
              }
              
              deployment_result = execute_deployment(deployment_info)
              
              json({
                message: 'Manual deployment completed',
                deployment: deployment_info,
                result: deployment_result
              })
              
            rescue StandardError => e
              status 500
              json({ 
                error: 'Manual deployment failed', 
                message: e.message 
              })
            end
          end
          
          # Deployment status endpoint
          app.get '/api/v1/deploy/status' do
            content_type :json
            
            begin
              # Get git status
              current_branch = `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
              current_commit = `git rev-parse HEAD 2>/dev/null`.strip
              last_commit_message = `git log -1 --pretty=%B 2>/dev/null`.strip
              
              # Check if we're behind remote
              behind_count = `git rev-list HEAD..origin/#{current_branch} --count 2>/dev/null`.strip.to_i
              
              # Check service status
              ha_status = check_home_assistant_status
              
              json({
                current_branch: current_branch,
                current_commit: current_commit[0..7],
                last_commit_message: last_commit_message,
                commits_behind: behind_count,
                needs_update: behind_count > 0,
                home_assistant_status: ha_status,
                last_check: Time.now.iso8601
              })
              
            rescue StandardError => e
              status 500
              json({ 
                error: 'Failed to get deployment status', 
                message: e.message 
              })
            end
          end
        end
        
        private
        
        # Validate GitHub webhook signature
        def self.validate_github_signature!(request, payload_body)
          secret = GlitchCube.config.deployment.github_webhook_secret
          signature = request.env['HTTP_X_HUB_SIGNATURE_256']
          
          unless signature
            raise SecurityError, 'Missing GitHub signature header'
          end
          
          # GitHub sends signature as "sha256=<hash>"
          expected_signature = "sha256=#{OpenSSL::HMAC.hexdigest('sha256', secret, payload_body)}"
          
          unless Rack::Utils.secure_compare(signature, expected_signature)
            raise SecurityError, 'GitHub signature validation failed'
          end
        end
        
        # Execute the deployment process
        def self.execute_deployment(deployment_info)
          results = []
          
          begin
            # Step 1: Git pull to update local repository
            puts "🔄 Pulling latest changes from git..."
            git_result = system('git pull origin main')
            results << {
              step: 'git_pull',
              success: git_result,
              message: git_result ? 'Git pull completed' : 'Git pull failed'
            }
            
            # Step 2: Sync configuration to Home Assistant
            puts "📤 Syncing configuration to Home Assistant..."
            config_result = system('bundle exec rake config:push')
            results << {
              step: 'config_sync',
              success: config_result,
              message: config_result ? 'Configuration sync completed' : 'Configuration sync failed'
            }
            
            # Step 3: Restart Home Assistant (if config sync succeeded)
            if config_result
              puts "🔄 Restarting Home Assistant..."
              ha_restart_result = system('ssh root@glitch.local "ha core restart"')
              results << {
                step: 'ha_restart',
                success: ha_restart_result,
                message: ha_restart_result ? 'Home Assistant restarted' : 'Home Assistant restart failed'
              }
            else
              results << {
                step: 'ha_restart',
                success: false,
                message: 'Skipped due to config sync failure'
              }
            end
            
            # Step 4: Restart Glitch Cube services if needed
            if git_result
              puts "🔄 Restarting Glitch Cube services..."
              service_restart_result = restart_services
              results << {
                step: 'service_restart',
                success: service_restart_result,
                message: service_restart_result ? 'Services restarted' : 'Service restart failed'
              }
            end
            
          rescue StandardError => e
            results << {
              step: 'deployment_error',
              success: false,
              message: "Deployment error: #{e.message}"
            }
          end
          
          # Log deployment results
          Services::LoggerService.log_api_call(
            service: 'deployment',
            endpoint: 'execute_deployment',
            deployment_info: deployment_info,
            results: results,
            overall_success: results.all? { |r| r[:success] }
          )
          
          results
        end
        
        # Check Home Assistant status
        def self.check_home_assistant_status
          begin
            ha_client = HomeAssistantClient.new
            states = ha_client.states
            {
              status: 'online',
              entities_count: states&.count || 0,
              last_check: Time.now.iso8601
            }
          rescue StandardError => e
            {
              status: 'offline',
              error: e.message,
              last_check: Time.now.iso8601
            }
          end
        end
        
        # Check if request is coming from Home Assistant
        def self.is_home_assistant_ip?(client_ip)
          # Allow local network IPs and localhost
          local_ips = [
            '127.0.0.1',           # localhost
            '::1',                 # IPv6 localhost
            'homeassistant',       # Docker service name
            /^192\.168\.\d+\.\d+$/, # 192.168.x.x
            /^172\.1[6-9]\.\d+\.\d+$/, # 172.16-19.x.x (Docker default)
            /^172\.2[0-9]\.\d+\.\d+$/, # 172.20-29.x.x (Docker default)
            /^172\.3[0-1]\.\d+\.\d+$/, # 172.30-31.x.x (Docker default)
            /^10\.\d+\.\d+\.\d+$/    # 10.x.x.x
          ]
          
          local_ips.any? do |pattern|
            if pattern.is_a?(Regexp)
              client_ip.match?(pattern)
            else
              client_ip == pattern
            end
          end
        end
        
        # Restart application services
        def self.restart_services
          begin
            # For Docker deployment, restart the containers
            if system('docker-compose ps > /dev/null 2>&1')
              puts "🐳 Restarting Docker services..."
              return system('docker-compose restart glitchcube sidekiq')
            end
            
            # For systemd deployment
            if system('systemctl is-active glitchcube.service > /dev/null 2>&1')
              puts "🔧 Restarting systemd services..."
              return system('sudo systemctl restart glitchcube.service glitchcube-sidekiq.service')
            end
            
            # Fallback: just return true (manual restart may be needed)
            puts "⚠️ No automatic service restart method detected"
            true
            
          rescue StandardError => e
            puts "❌ Service restart failed: #{e.message}"
            false
          end
        end
      end
    end
  end
end