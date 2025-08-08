# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/modules/error_handling'
require_relative '../../lib/services/logger_service'

RSpec.describe ErrorHandling do
  let(:test_class) do
    Class.new do
      include ErrorHandling
    end
  end

  let(:instance) { test_class.new }

  describe '#log_error' do
    context 'when reraise is true' do
      it 'logs the error and re-raises it' do
        error = StandardError.new('Test error')
        context = { operation: 'test_operation' }

        expect(Services::LoggerService).to receive(:log_api_call).with(
          hash_including(
            service: 'application',
            endpoint: 'test_operation',
            status: 500,
            error: 'StandardError: Test error',
            error_class: 'StandardError'
          )
        )

        expect do
          instance.log_error(error, context)
        end.to raise_error(StandardError, 'Test error')
      end
    end

    context 'when reraise is false' do
      it 'logs the error without re-raising' do
        error = StandardError.new('Test error')
        context = { operation: 'test_operation' }

        expect(Services::LoggerService).to receive(:log_api_call).with(
          hash_including(
            service: 'application',
            endpoint: 'test_operation',
            status: 500,
            error: 'StandardError: Test error',
            error_class: 'StandardError'
          )
        )

        expect do
          instance.log_error(error, context, reraise: false)
        end.not_to raise_error
      end
    end
  end

  describe '#handle_operational_error' do
    it 'logs the error as operational and returns the fallback value' do
      error = ErrorHandling::ServiceUnavailableError.new('Service down')
      fallback = { default: 'response' }
      context = { service: 'test_service' }

      expect(Services::LoggerService).to receive(:log_api_call).with(
        hash_including(
          service: 'test_service',
          endpoint: 'unknown',
          status: 500,
          error: 'ErrorHandling::ServiceUnavailableError: Service down',
          error_class: 'ErrorHandling::ServiceUnavailableError',
          operational: true
        )
      )

      result = instance.handle_operational_error(error, fallback, context)
      expect(result).to eq(fallback)
    end
  end

  describe '#with_error_handling' do
    context 'when block executes successfully' do
      it 'returns the block result' do
        result = instance.with_error_handling('test_operation') do
          'success'
        end

        expect(result).to eq('success')
      end
    end

    context 'when a CircuitBreaker::CircuitOpenError occurs' do
      it 'handles it as an operational error and returns fallback' do
        # Mock the CircuitBreaker error class
        stub_const('CircuitBreaker::CircuitOpenError', Class.new(StandardError))
        error = CircuitBreaker::CircuitOpenError.new('Circuit open')
        fallback = 'default_value'

        expect(Services::LoggerService).to receive(:log_api_call).with(
          hash_including(
            service: 'application',
            endpoint: 'test_operation',
            status: 500,
            error: 'CircuitBreaker::CircuitOpenError: Circuit open',
            operation: 'test_operation',
            type: 'circuit_breaker',
            operational: true
          )
        )

        result = instance.with_error_handling('test_operation', fallback: fallback) do
          raise error
        end

        expect(result).to eq(fallback)
      end
    end

    context 'when a network timeout occurs' do
      it 'handles it as an operational error' do
        error = Net::OpenTimeout.new('Connection timeout')
        fallback = []

        expect(Services::LoggerService).to receive(:log_api_call).with(
          hash_including(
            service: 'application',
            endpoint: 'network_call',
            status: 500,
            error: 'Net::OpenTimeout: Connection timeout',
            operation: 'network_call',
            type: 'timeout',
            operational: true
          )
        )

        result = instance.with_error_handling('network_call', fallback: fallback) do
          raise error
        end

        expect(result).to eq(fallback)
      end
    end

    context 'when an unexpected error occurs' do
      context 'with reraise_unexpected: true' do
        it 'logs and re-raises the error' do
          error = StandardError.new('Unexpected error')

          expect(Services::LoggerService).to receive(:log_api_call).with(
            hash_including(
              service: 'application',
              endpoint: 'critical_operation',
              status: 500,
              error: 'StandardError: Unexpected error',
              operation: 'critical_operation',
              unexpected: true
            )
          )

          expect do
            instance.with_error_handling('critical_operation', reraise_unexpected: true) do
              raise error
            end
          end.to raise_error(StandardError, 'Unexpected error')
        end
      end

      context 'with reraise_unexpected: false' do
        it 'logs the error and returns fallback' do
          error = StandardError.new('Unexpected error')
          fallback = nil

          expect(Services::LoggerService).to receive(:log_api_call).with(
            hash_including(
              service: 'application',
              endpoint: 'non_critical_operation',
              status: 500,
              error: 'StandardError: Unexpected error',
              operation: 'non_critical_operation',
              unexpected: true
            )
          )

          result = instance.with_error_handling('non_critical_operation', fallback: fallback, reraise_unexpected: false) do
            raise error
          end

          expect(result).to eq(fallback)
        end
      end
    end
  end

end