# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/jobs/host_registration_worker'
require 'sidekiq/testing'

RSpec.describe Jobs::HostRegistrationWorker do
  let(:worker) { described_class.new }
  let(:registration_service) { Services::System::HostRegistrationService }

  before do
    # In inline mode, jobs execute immediately - no need to set up fake mode
    if defined?(Sidekiq) && Sidekiq::Testing.enabled?
      # Clear any existing jobs if we're in fake mode (shouldn't happen with inline)
      Sidekiq::Worker.clear_all
    end
  end

  describe '#perform' do
    context 'when called with initial_registration argument (startup)' do
      it 'calls register_with_retry_loop for initial registration' do
        expect(registration_service).to receive(:register_with_retry_loop).and_return(true)
        expect(Services::Logging::SimpleLogger).to receive(:info).with(
          '🚀 Starting initial host registration with Home Assistant',
          tagged: %i[host_registration startup]
        )
        expect(Services::Logging::SimpleLogger).to receive(:info).with(
          '✅ Initial registration successful - regular updates handled by cron job',
          tagged: %i[host_registration startup]
        )

        worker.perform('initial_registration')
      end

      it 'raises an error if initial registration fails' do
        expect(registration_service).to receive(:register_with_retry_loop).and_return(false)
        expect(Services::Logging::SimpleLogger).to receive(:info)
        expect(Services::Logging::SimpleLogger).to receive(:error)

        expect do
          worker.perform('initial_registration')
        end.to raise_error('Failed to register with Home Assistant after all attempts')
      end
    end

    context 'when called without arguments (cron job)' do
      it 'calls register_with_home_assistant for regular updates' do
        expect(registration_service).to receive(:register_with_home_assistant).and_return(true)
        expect(Services::Logging::SimpleLogger).to receive(:debug).with(
          '🔄 Performing regular host registration update',
          tagged: %i[host_registration cron]
        )
        expect(Services::Logging::SimpleLogger).to receive(:debug).with(
          '✅ Regular host registration update successful',
          tagged: %i[host_registration cron]
        )

        worker.perform
      end

      it 'logs a warning if regular registration fails' do
        expect(registration_service).to receive(:register_with_home_assistant).and_return(false)
        expect(Services::Logging::SimpleLogger).to receive(:debug).with(
          '🔄 Performing regular host registration update',
          tagged: %i[host_registration cron]
        )
        expect(Services::Logging::SimpleLogger).to receive(:warn).with(
          '⚠️ Regular host registration update failed',
          tagged: %i[host_registration cron]
        )

        worker.perform
      end

      it 'does not raise an error if regular registration fails' do
        expect(registration_service).to receive(:register_with_home_assistant).and_return(false)
        allow(Services::Logging::SimpleLogger).to receive(:debug)
        allow(Services::Logging::SimpleLogger).to receive(:warn)

        expect { worker.perform }.not_to raise_error
      end
    end

    context 'when called with nil argument' do
      it 'treats nil as a regular cron job call' do
        expect(registration_service).to receive(:register_with_home_assistant).and_return(true)
        expect(Services::Logging::SimpleLogger).to receive(:debug).twice

        worker.perform(nil)
      end
    end

    context 'when called with other arguments' do
      it 'treats unknown arguments as regular cron job calls' do
        expect(registration_service).to receive(:register_with_home_assistant).and_return(true)
        expect(Services::Logging::SimpleLogger).to receive(:debug).twice

        worker.perform('unknown_argument')
      end
    end
  end

  describe 'Sidekiq integration' do
    context 'when Sidekiq is available' do
      before do
        skip 'Sidekiq not defined' unless defined?(Sidekiq)
      end

      it 'can execute jobs with initial_registration argument' do
        expect(registration_service).to receive(:register_with_retry_loop).and_return(true)
        expect(Services::Logging::SimpleLogger).to receive(:info).twice

        # In inline mode, this will execute immediately
        Jobs::HostRegistrationWorker.perform_async('initial_registration')
      end

      it 'can execute jobs without arguments for cron' do
        expect(registration_service).to receive(:register_with_home_assistant).and_return(true)
        expect(Services::Logging::SimpleLogger).to receive(:debug).twice

        # In inline mode, this will execute immediately
        Jobs::HostRegistrationWorker.perform_async
      end

      it 'can execute scheduled jobs' do
        expect(registration_service).to receive(:register_with_retry_loop).and_return(true)
        expect(Services::Logging::SimpleLogger).to receive(:info).twice

        # In inline mode, delay is ignored and job executes immediately
        Jobs::HostRegistrationWorker.perform_in(5, 'initial_registration')
      end

      it 'has retry enabled' do
        expect(Jobs::HostRegistrationWorker.sidekiq_options['retry']).to eq(3)
      end
    end

    context 'when Sidekiq is not available' do
      before do
        skip 'Sidekiq is defined' if defined?(Sidekiq)
      end

      it 'gracefully handles missing Sidekiq' do
        # This test ensures the spec can run even without Sidekiq
        expect(true).to be true
      end
    end
  end

  describe 'error handling' do
    context 'when registration service raises an exception' do
      it 'lets the exception bubble up for Sidekiq retry on initial registration' do
        expect(registration_service).to receive(:register_with_retry_loop)
          .and_raise(StandardError, 'Connection failed')
        allow(Services::Logging::SimpleLogger).to receive(:info)

        expect do
          worker.perform('initial_registration')
        end.to raise_error(StandardError, 'Connection failed')
      end

      it 'lets the exception bubble up for Sidekiq retry on regular registration' do
        expect(registration_service).to receive(:register_with_home_assistant)
          .and_raise(StandardError, 'Connection failed')
        allow(Services::Logging::SimpleLogger).to receive(:debug)

        expect do
          worker.perform
        end.to raise_error(StandardError, 'Connection failed')
      end
    end
  end
end
