# frozen_string_literal: true

require 'spec_helper'
require 'sidekiq/testing'

RSpec.describe HostRegistrationWorker do
  describe '#perform' do
    context 'when performing regular registration' do
      it 'calls register_with_home_assistant' do
        expect(Services::HostRegistrationService).to receive(:register_with_home_assistant)

        described_class.new.perform
      end

      it 'uses default parameters when none provided' do
        expect(Services::HostRegistrationService).to receive(:register_with_home_assistant)

        described_class.new.perform
      end
    end

    context 'when performing initial registration' do
      context 'when registration succeeds' do
        before do
          allow(Services::HostRegistrationService).to receive(:register_with_retry_loop).and_return(true)
          allow(Services::SimpleLogger).to receive(:info)
        end

        it 'calls register_with_retry_loop' do
          expect(Services::HostRegistrationService).to receive(:register_with_retry_loop).and_return(true)

          described_class.new.perform(initial_registration: true)
        end

        it 'logs success message' do
          expect(Services::SimpleLogger).to receive(:info).with(
            '✅ Initial registration successful - regular updates handled by cron job',
            tagged: %i[host_registration startup]
          )

          described_class.new.perform(initial_registration: true)
        end
      end

      context 'when registration fails' do
        before do
          allow(Services::HostRegistrationService).to receive(:register_with_retry_loop).and_return(false)
          allow(Services::SimpleLogger).to receive(:error)
        end

        it 'logs error message' do
          expect(Services::SimpleLogger).to receive(:error).with(
            '❌ Initial registration failed - will retry via Sidekiq retry mechanism',
            tagged: %i[host_registration startup error]
          )

          expect { described_class.new.perform(initial_registration: true) }
            .to raise_error('Failed to register with Home Assistant after all attempts')
        end

        it 'raises error for Sidekiq retry' do
          expect { described_class.new.perform(initial_registration: true) }
            .to raise_error('Failed to register with Home Assistant after all attempts')
        end
      end
    end
  end

  describe 'Sidekiq integration' do
    it 'has correct queue configuration' do
      expect(described_class.sidekiq_options['queue']).to eq(:default)
    end

    it 'has correct retry configuration' do
      expect(described_class.sidekiq_options['retry']).to eq(3)
    end
  end
end
