# frozen_string_literal: true

# Mac Mini specific deployment routes
# These routes are conditionally loaded when deployment.mac_mini is enabled

module GlitchCube
  module Routes
    module Deploy
      def self.registered(app)
        # Mac Mini specific deployment health check
        app.get '/deploy/health' do
          content_type :json
          
          begin
            # Check Mac Mini specific deployment status
            status = {
              mac_mini_deployment: true,
              timestamp: Time.now.iso8601,
              git_status: check_git_status,
              services_status: check_services_status
            }
            
            json(status)
          rescue StandardError => e
            status 500
            json({
              error: 'Mac Mini deployment health check failed',
              message: e.message,
              timestamp: Time.now.iso8601
            })
          end
        end
        
        # Mac Mini specific deployment trigger
        app.post '/deploy/trigger' do
          content_type :json
          
          begin
            # Simple authentication check
            api_key = request.env['HTTP_X_API_KEY'] || params['api_key']
            unless api_key == GlitchCube.config.deployment&.api_key
              status 401
              return json({ error: 'Invalid API key' })
            end
            
            # Trigger Mac Mini specific deployment
            deployment_info = {
              type: 'mac_mini_deployment',
              timestamp: Time.now.iso8601,
              triggered_by: 'manual'
            }
            
            # Log the deployment request
            Services::LoggerService.log_api_call(
              service: 'mac_mini_deployment',
              endpoint: '/deploy/trigger',
              method: 'POST',
              deployment_info: deployment_info
            )
            
            json({
              message: 'Mac Mini deployment triggered',
              deployment: deployment_info,
              success: true
            })
            
          rescue StandardError => e
            status 500
            json({
              error: 'Mac Mini deployment trigger failed',
              message: e.message
            })
          end
        end
      end
      
      private
      
      def self.check_git_status
        {
          current_branch: `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip,
          current_commit: `git rev-parse HEAD 2>/dev/null`.strip[0..7],
          status: 'ok'
        }
      rescue StandardError => e
        { status: 'error', message: e.message }
      end
      
      def self.check_services_status
        {
          sinatra: 'running',
          sidekiq: system('pgrep -f sidekiq > /dev/null') ? 'running' : 'stopped',
          timestamp: Time.now.iso8601
        }
      rescue StandardError => e
        { status: 'error', message: e.message }
      end
    end
  end
end