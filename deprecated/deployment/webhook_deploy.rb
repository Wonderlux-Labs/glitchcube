# frozen_string_literal: true

# Webhook handler for GitHub deployment triggers
# This handles deployment for both the Mac host (Sinatra) and VM (Home Assistant)

require 'English'
require 'json'
require 'openssl'

module GlitchCube
  module Routes
    module WebhookDeploy
      def self.registered(app)
        app.post '/webhook/deploy' do
          # Read the request body
          request.body.rewind
          payload_body = request.body.read

          # Verify GitHub webhook signature
          signature = request.env['HTTP_X_HUB_SIGNATURE_256']

          if signature.nil?
            logger.warn 'Webhook deploy: Missing signature'
            halt 401, json(error: 'Missing signature')
          end

          # Calculate expected signature
          webhook_secret = ENV.fetch('GITHUB_WEBHOOK_SECRET', '')
          if webhook_secret.empty?
            logger.error 'GITHUB_WEBHOOK_SECRET not configured!'
            halt 500, json(error: 'Webhook secret not configured')
          end

          expected_signature = 'sha256=' + OpenSSL::HMAC.hexdigest(
            OpenSSL::Digest.new('sha256'),
            webhook_secret,
            payload_body
          )

          # Secure comparison to prevent timing attacks
          unless Rack::Utils.secure_compare(expected_signature, signature)
            logger.warn 'Webhook deploy: Invalid signature'
            halt 401, json(error: 'Invalid signature')
          end

          # Parse the payload
          payload = JSON.parse(payload_body)

          # Check if this is a push to the main branch
          if payload['ref'] != 'refs/heads/main'
            logger.info "Webhook deploy: Push to non-main branch (#{payload['ref']}), ignoring"
            return json(status: 'ignored', reason: 'not main branch')
          end

          logger.info 'Webhook deploy: Valid push to main branch detected'
          logger.info "Webhook deploy: Commit: #{payload['after'][0..7]}"

          # Trigger deployments in background to avoid blocking the webhook response
          Thread.new do
            deploy_to_vm
            deploy_to_host
          rescue StandardError => e
            logger.error "Webhook deploy failed: #{e.message}"
            logger.error e.backtrace.join("\n")
          end

          status 202 # Accepted
          json(
            status: 'accepted',
            message: 'Deployment initiated',
            commit: payload['after'][0..7]
          )
        rescue JSON::ParserError => e
          logger.error "Webhook deploy: Invalid JSON - #{e.message}"
          halt 400, json(error: 'Invalid JSON payload')
        rescue StandardError => e
          logger.error "Webhook deploy error: #{e.message}"
          logger.error e.backtrace.join("\n")
          halt 500, json(error: 'Internal server error')
        end

        private

        def deploy_to_vm
          logger.info 'Deploying to Home Assistant VM...'

          vm_host = ENV.fetch('HA_VM_HOST', 'homeassistant.local')
          vm_user = ENV.fetch('HA_VM_USER', 'homeassistant')
          ssh_key = ENV.fetch('HA_VM_SSH_KEY', File.expand_path('~/.ssh/ha_vm_updater'))

          unless File.exist?(ssh_key)
            logger.error "SSH key not found at #{ssh_key}"
            return false
          end

          # SSH to VM and run update script
          cmd = [
            'ssh',
            '-i', ssh_key,
            '-o', 'StrictHostKeyChecking=no',
            '-o', 'ConnectTimeout=10',
            "#{vm_user}@#{vm_host}",
            '/usr/local/bin/update_ha_config.sh'
          ].join(' ')

          logger.info "Executing: #{cmd.gsub(ssh_key, 'SSH_KEY')}"
          result = system(cmd)

          if result
            logger.info 'VM deployment completed successfully'
          else
            logger.error "VM deployment failed with exit code: #{$CHILD_STATUS.exitstatus}"
          end

          result
        end

        def deploy_to_host
          logger.info 'Deploying Sinatra application on host...'

          # Pull latest changes
          logger.info 'Pulling latest changes...'
          unless system('git pull origin main')
            logger.error 'Git pull failed'
            return false
          end

          # Bundle install if Gemfile changed
          if File.mtime('Gemfile.lock') > (Time.now - 300) # Changed in last 5 minutes
            logger.info 'Installing gem dependencies...'
            unless system('bundle install')
              logger.error 'Bundle install failed'
              return false
            end
          end

          # Restart the service
          logger.info 'Restarting Sinatra service...'

          # Try different restart methods
          if system('which launchctl > /dev/null 2>&1')
            # macOS launchd
            plist = File.expand_path('~/Library/LaunchAgents/com.glitchcube.plist')
            if File.exist?(plist)
              system("launchctl unload #{plist} 2>/dev/null")
              sleep 1
              system("launchctl load #{plist}")
            else
              logger.warn "LaunchAgent plist not found at #{plist}"
            end
          elsif system('which systemctl > /dev/null 2>&1')
            # Linux systemd
            system('sudo systemctl restart glitchcube')
          else
            logger.warn 'No service manager found, manual restart required'
          end

          logger.info 'Host deployment completed'
          true
        end
      end
    end
  end
end
