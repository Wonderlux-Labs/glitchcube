# frozen_string_literal: true

require 'spec_helper'

RSpec.describe MissedDeploymentWorker do
  let(:worker) { described_class.new }

  let(:deployment_info) do
    {
      'repository' => 'glitchcube',
      'branch' => 'main',
      'commit_sha' => 'abc123',
      'commit_message' => 'Fix deployment issue',
      'committer' => 'test_user',
      'timestamp' => Time.now.iso8601
    }
  end

  describe '#perform' do
    context 'when deployment succeeds' do
      it 'executes deployment and logs success' do
        # Mock successful deployment results
        success_results = [
          { step: 'git_pull', success: true, message: 'Git pull completed' },
          { step: 'config_sync', success: true, message: 'Configuration sync completed' },
          { step: 'ha_restart', success: true, message: 'Home Assistant restarted' },
          { step: 'service_restart', success: true, message: 'Services restarted' }
        ]

        allow(GlitchCube::Routes::Api::Deployment)
          .to receive(:execute_deployment)
          .and_return(success_results)

        allow(Services::LoggerService)
          .to receive(:log_api_call)

        result = worker.perform(deployment_info)

        expect(result).to eq(success_results)
        expect(Services::LoggerService)
          .to have_received(:log_api_call)
          .with(hash_including(
                  service: 'missed_deployment_worker',
                  success: true,
                  message: 'Missed deployment recovery completed successfully'
                ))
      end
    end

    context 'when deployment fails' do
      it 'raises error and logs failure' do
        # Mock failed deployment results
        failed_results = [
          { step: 'git_pull', success: true, message: 'Git pull completed' },
          { step: 'config_sync', success: false, message: 'Configuration sync failed' },
          { step: 'ha_restart', success: false, message: 'Skipped due to config sync failure' }
        ]

        allow(GlitchCube::Routes::Api::Deployment)
          .to receive(:execute_deployment)
          .and_return(failed_results)

        allow(Services::LoggerService)
          .to receive(:log_api_call)

        expect { worker.perform(deployment_info) }
          .to raise_error('Deployment failed at: config_sync, ha_restart')

        expect(Services::LoggerService)
          .to have_received(:log_api_call)
          .with(hash_including(
                  service: 'missed_deployment_worker',
                  success: false,
                  failed_steps: %w[config_sync ha_restart]
                ))
      end
    end

    context 'when deployment raises exception' do
      it 'logs error and re-raises for Sidekiq retry' do
        error = StandardError.new('Git connection failed')

        allow(GlitchCube::Routes::Api::Deployment)
          .to receive(:execute_deployment)
          .and_raise(error)

        allow(Services::LoggerService)
          .to receive(:log_api_call)

        expect { worker.perform(deployment_info) }
          .to raise_error('Git connection failed')

        expect(Services::LoggerService)
          .to have_received(:log_api_call)
          .with(hash_including(
                  service: 'missed_deployment_worker',
                  status: 500,
                  error: 'Git connection failed'
                ))
      end
    end

    context 'with minimal deployment info' do
      it 'uses defaults for missing fields' do
        minimal_info = { 'commit_sha' => 'def456' }

        allow(GlitchCube::Routes::Api::Deployment)
          .to receive(:execute_deployment) do |deployment_data|
            expect(deployment_data[:repository]).to eq('startup_recovery')
            expect(deployment_data[:branch]).to eq('main')
            expect(deployment_data[:commit_sha]).to eq('def456')
            expect(deployment_data[:commit_message]).to eq('Missed deployment recovery on startup')
            expect(deployment_data[:triggered_by]).to eq('missed_deployment_recovery')

            [{ step: 'test', success: true, message: 'Test completed' }]
          end

        worker.perform(minimal_info)
      end
    end
  end

  describe 'Sidekiq configuration' do
    it 'has correct queue and retry settings' do
      expect(described_class.sidekiq_options_hash).to include(
        'queue' => :default,  # Sidekiq uses symbols for queue names
        'retry' => 2
      )
    end
  end
end
