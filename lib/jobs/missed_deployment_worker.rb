# frozen_string_literal: true

class MissedDeploymentWorker
  include Sidekiq::Job

  # Run once, with retries for transient failures
  sidekiq_options retry: 2, queue: :default

  def perform(deployment_info = {})
    puts '🚀 Starting missed deployment recovery...'

    # Prepare deployment info with defaults
    deployment_data = {
      repository: deployment_info['repository'] || 'startup_recovery',
      branch: deployment_info['branch'] || 'main',
      commit_sha: deployment_info['commit_sha'] || 'recovery',
      commit_message: deployment_info['commit_message'] || 'Missed deployment recovery on startup',
      committer: deployment_info['committer'] || 'system',
      timestamp: deployment_info['timestamp'] || Time.now.iso8601,
      triggered_by: 'missed_deployment_recovery'
    }

    Services::LoggerService.log_api_call(
      service: 'missed_deployment_worker',
      endpoint: 'perform',
      method: 'POST',
      deployment_info: deployment_data,
      message: 'Starting missed deployment recovery'
    )

    # Use the same deployment execution logic as the API
    results = GlitchCube::Routes::Api::Deployment.send(:execute_deployment, deployment_data)

    overall_success = results.all? { |r| r[:success] }

    if overall_success
      puts '✅ Missed deployment recovery completed successfully'
      Services::LoggerService.log_api_call(
        service: 'missed_deployment_worker',
        endpoint: 'perform',
        method: 'POST',
        deployment_info: deployment_data,
        results: results,
        success: true,
        message: 'Missed deployment recovery completed successfully'
      )
    else
      failed_steps = results.reject { |r| r[:success] }.map { |r| r[:step] }
      puts "❌ Missed deployment recovery failed at: #{failed_steps.join(', ')}"

      Services::LoggerService.log_api_call(
        service: 'missed_deployment_worker',
        endpoint: 'perform',
        method: 'POST',
        deployment_info: deployment_data,
        results: results,
        success: false,
        failed_steps: failed_steps,
        message: 'Missed deployment recovery failed'
      )

      raise "Deployment failed at: #{failed_steps.join(', ')}"
    end

    results
  rescue StandardError => e
    puts "❌ Missed deployment worker error: #{e.message}"

    Services::LoggerService.log_api_call(
      service: 'missed_deployment_worker',
      endpoint: 'perform',
      method: 'POST',
      status: 500,
      error: e.message,
      backtrace: e.backtrace.first(3)
    )

    # Re-raise so Sidekiq can handle retries
    raise e
  end
end
