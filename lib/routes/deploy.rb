# frozen_string_literal: true

# Simple deployment webhook for Sinatra app
# This handles self-deployment when GitHub Actions triggers it

require 'json'
require 'openssl'
require_relative '../cube/settings'

module GlitchCube
  module Routes
    module Deploy
      def self.registered(app)
        app.post '/deploy' do
          # Read the request body
          request.body.rewind
          payload_body = request.body.read

          # Verify GitHub webhook signature (optional but recommended)
          signature = request.env['HTTP_X_HUB_SIGNATURE_256']

          if signature && Cube::Settings.github_webhook_secret
            expected_signature = 'sha256=' + OpenSSL::HMAC.hexdigest(
              OpenSSL::Digest.new('sha256'),
              Cube::Settings.github_webhook_secret,
              payload_body
            )

            unless Rack::Utils.secure_compare(expected_signature, signature)
              logger.warn 'Deploy webhook: Invalid signature'
              halt 401, json(error: 'Invalid signature')
            end
          end

          # Parse payload to check branch (optional)
          begin
            payload = JSON.parse(payload_body)
            if payload['ref'] && payload['ref'] != 'refs/heads/main'
              logger.info "Deploy: Ignoring non-main branch (#{payload['ref']})"
              return json(status: 'ignored', reason: 'not main branch')
            end
          rescue JSON::ParserError
            # If we can't parse it, still proceed with deployment
            logger.warn 'Deploy: Could not parse JSON payload, proceeding anyway'
          end

          logger.info 'Deploy: Starting deployment process...'

          # Run deployment in background to not block webhook response
          Thread.new do
            deploy_sinatra_app
          rescue StandardError => e
            logger.error "Deploy failed: #{e.message}"
            logger.error e.backtrace.join("\n")
          end

          status 202 # Accepted
          json(status: 'accepted', message: 'Deployment initiated')
        rescue StandardError => e
          logger.error "Deploy webhook error: #{e.message}"
          logger.error e.backtrace.join("\n")
          halt 500, json(error: 'Internal server error')
        end

        app.helpers do
          def deploy_sinatra_app
            app_dir = File.expand_path('../..', __dir__) # Go up to app root

            logger.info "Deploy: Changing to app directory: #{app_dir}"
            Dir.chdir(app_dir) do
              # Pull latest changes
              logger.info 'Deploy: Pulling latest changes from git...'
              result = system('git pull origin main 2>&1')
              unless result
                logger.error 'Deploy: Git pull failed!'
                return false
              end

              # Check if Gemfile was updated
              gemfile_changed = `git diff HEAD@{1} HEAD --name-only`.include?('Gemfile')

              if gemfile_changed
                logger.info 'Deploy: Gemfile changed, running bundle install...'
                result = system('bundle install 2>&1')
                unless result
                  logger.error 'Deploy: Bundle install failed!'
                  return false
                end
              end

              # Restart the application
              logger.info 'Deploy: Restarting Sinatra application...'

              # Try different restart methods based on what's available
              restarted = false

              # Method 1: Touch tmp/restart.txt (works with Passenger)
              if File.exist?('tmp')
                system('touch tmp/restart.txt')
                logger.info 'Deploy: Touched tmp/restart.txt'
                restarted = true
              end

              # Method 2: macOS launchctl
              if system('which launchctl > /dev/null 2>&1')
                plist_path = File.expand_path('~/Library/LaunchAgents/com.glitchcube.plist')
                if File.exist?(plist_path)
                  logger.info 'Deploy: Restarting via launchctl...'
                  system("launchctl unload #{plist_path} 2>/dev/null")
                  sleep 1
                  system("launchctl load #{plist_path}")
                  restarted = true
                end
              end

              # Method 3: systemd (Linux)
              if !restarted && system('which systemctl > /dev/null 2>&1')
                logger.info 'Deploy: Restarting via systemctl...'
                system('sudo systemctl restart glitchcube')
                restarted = true
              end

              # Method 4: Kill and restart (last resort)
              unless restarted
                logger.warn 'Deploy: No service manager found, attempting process restart...'
                # This will kill the current process, relying on process manager to restart
                begin
                  Process.kill('USR2', Process.pid)
                rescue StandardError
                  nil
                end
              end

              logger.info 'Deploy: Deployment completed successfully!'
            end

            true
          end
        end
      end
    end
  end
end
