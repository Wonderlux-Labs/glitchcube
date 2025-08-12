# frozen_string_literal: true

require 'spec_helper'
require 'sidekiq/testing'

RSpec.describe HostRegistrationWorker do
  let(:worker) { described_class.new }
  let(:registration_service) { Services::HostRegistrationService }

  before do
    Sidekiq::Testing.fake!
    Sidekiq::Worker.clear_all
  end

  describe '#perform' do
    context 'when called with initial_registration argument (startup)' do
      it 'calls register_with_retry_loop for initial registration' do
        expect(registration_service).to receive(:register_with_retry_loop).and_return(true)
        expect(Services::SimpleLogger).to receive(:info).with(
          '🚀 Starting initial host registration with Home Assistant',
          tagged: %i[host_registration startup]
        )
        expect(Services::SimpleLogger).to receive(:info).with(
          '✅ Initial registration successful - regular updates handled by cron job',
          tagged: %i[host_registration startup]
        )

        worker.perform('initial_registration')
      end

      it 'raises an error if initial registration fails' do
        expect(registration_service).to receive(:register_with_retry_loop).and_return(false)
        expect(Services::SimpleLogger).to receive(:info)
        expect(Services::SimpleLogger).to receive(:error)

        expect do
          worker.perform('initial_registration')
        end.to raise_error('Failed to register with Home Assistant after all attempts')
      end
    end

    context 'when called without arguments (cron job)' do
      it 'calls register_with_home_assistant for regular updates' do
        expect(registration_service).to receive(:register_with_home_assistant).and_return(true)
        expect(Services::SimpleLogger).to receive(:debug).with(
          '🔄 Performing regular host registration update',
          tagged: %i[host_registration cron]
        )
        expect(Services::SimpleLogger).to receive(:debug).with(
          '✅ Regular host registration update successful',
          tagged: %i[host_registration cron]
        )

        worker.perform
      end

      it 'logs a warning if regular registration fails' do
        expect(registration_service).to receive(:register_with_home_assistant).and_return(false)
        expect(Services::SimpleLogger).to receive(:debug).with(
          '🔄 Performing regular host registration update',
          tagged: %i[host_registration cron]
        )
        expect(Services::SimpleLogger).to receive(:warn).with(
          '⚠️ Regular host registration update failed',
          tagged: %i[host_registration cron]
        )

        worker.perform
      end

      it 'does not raise an error if regular registration fails' do
        expect(registration_service).to receive(:register_with_home_assistant).and_return(false)
        allow(Services::SimpleLogger).to receive(:debug)
        allow(Services::SimpleLogger).to receive(:warn)

        expect { worker.perform }.not_to raise_error
      end
    end

    context 'when called with nil argument' do
      it 'treats nil as a regular cron job call' do
        expect(registration_service).to receive(:register_with_home_assistant).and_return(true)
        expect(Services::SimpleLogger).to receive(:debug).twice

        worker.perform(nil)
      end
    end

    context 'when called with other arguments' do
      it 'treats unknown arguments as regular cron job calls' do
        expect(registration_service).to receive(:register_with_home_assistant).and_return(true)
        expect(Services::SimpleLogger).to receive(:debug).twice

        worker.perform('unknown_argument')
      end
    end
  end

  describe 'Sidekiq integration' do
    it 'can be enqueued with initial_registration argument' do
      expect do
        HostRegistrationWorker.perform_async('initial_registration')
      end.to change(HostRegistrationWorker.jobs, :size).by(1)

      job = HostRegistrationWorker.jobs.last
      expect(job['args']).to eq(['initial_registration'])
    end

    it 'can be enqueued without arguments for cron' do
      expect do
        HostRegistrationWorker.perform_async
      end.to change(HostRegistrationWorker.jobs, :size).by(1)

      job = HostRegistrationWorker.jobs.last
      expect(job['args']).to eq([])
    end

    it 'can be scheduled with delay' do
      expect do
        HostRegistrationWorker.perform_in(5, 'initial_registration')
      end.to change(HostRegistrationWorker.jobs, :size).by(1)

      job = HostRegistrationWorker.jobs.last
      expect(job['args']).to eq(['initial_registration'])
      expect(job['at']).to be_within(1).of(Time.now.to_f + 5)
    end

    it 'uses the default queue' do
      HostRegistrationWorker.perform_async
      job = HostRegistrationWorker.jobs.last
      expect(job['queue']).to eq('default')
    end

    it 'has retry enabled' do
      expect(HostRegistrationWorker.sidekiq_options['retry']).to eq(3)
    end
  end

  describe 'error handling' do
    context 'when registration service raises an exception' do
      it 'lets the exception bubble up for Sidekiq retry on initial registration' do
        expect(registration_service).to receive(:register_with_retry_loop)
          .and_raise(StandardError, 'Connection failed')
        allow(Services::SimpleLogger).to receive(:info)

        expect do
          worker.perform('initial_registration')
        end.to raise_error(StandardError, 'Connection failed')
      end

      it 'lets the exception bubble up for Sidekiq retry on regular registration' do
        expect(registration_service).to receive(:register_with_home_assistant)
          .and_raise(StandardError, 'Connection failed')
        allow(Services::SimpleLogger).to receive(:debug)

        expect do
          worker.perform
        end.to raise_error(StandardError, 'Connection failed')
      end
    end
  end
end
