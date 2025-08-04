# frozen_string_literal: true

require 'spec_helper'

RSpec.describe CircuitBreaker do
  let(:circuit_breaker) { described_class.new(name: 'test_service', failure_threshold: 3, recovery_timeout: 1, success_threshold: 1) }

  describe '#initialize' do
    it 'starts in closed state' do
      expect(circuit_breaker.state).to eq(:closed)
    end

    it 'initializes with zero failures' do
      expect(circuit_breaker.failure_count).to eq(0)
    end

    it 'sets the name' do
      expect(circuit_breaker.name).to eq('test_service')
    end
  end

  describe '#call' do
    context 'when circuit is closed' do
      it 'executes the block successfully' do
        result = circuit_breaker.call { 'success' }
        expect(result).to eq('success')
      end

      it 'resets failure count on success' do
        # Create some failures first
        2.times do
          circuit_breaker.call { raise StandardError, 'test error' }
        rescue StandardError
          # Ignore for this test
        end

        expect(circuit_breaker.failure_count).to eq(2)

        # Successful call should reset failures
        circuit_breaker.call { 'success' }
        expect(circuit_breaker.failure_count).to eq(0)
      end

      it 'records failures and opens circuit after threshold' do
        # Generate failures up to threshold
        2.times do
          expect do
            circuit_breaker.call { raise StandardError, 'test error' }
          end.to raise_error(StandardError)
        end

        expect(circuit_breaker.state).to eq(:closed)
        expect(circuit_breaker.failure_count).to eq(2)

        # One more failure should open the circuit
        expect do
          circuit_breaker.call { raise StandardError, 'final error' }
        end.to raise_error(StandardError)

        expect(circuit_breaker.state).to eq(:open)
        expect(circuit_breaker.failure_count).to eq(3)
      end
    end

    context 'when circuit is open' do
      before do
        # Force circuit open by exceeding failure threshold
        3.times do
          circuit_breaker.call { raise StandardError, 'test error' }
        rescue StandardError
          # Ignore for this test
        end
      end

      it 'raises CircuitOpenError without executing block' do
        expect(circuit_breaker.state).to eq(:open)

        expect do
          circuit_breaker.call { 'should not execute' }
        end.to raise_error(CircuitBreaker::CircuitOpenError)
      end

      it 'attempts reset after recovery timeout' do
        expect(circuit_breaker.state).to eq(:open)

        # Wait a moment for recovery timeout (since we set it to 1 second)
        sleep(1.1)

        # Should attempt to go to half-open state and then close on success
        result = circuit_breaker.call { 'test recovery' }

        expect(result).to eq('test recovery')
        # After successful call, should be closed (since success_threshold: 1)
        expect(circuit_breaker.state).to eq(:closed)
      end
    end

    context 'when circuit is half-open' do
      before do
        # Force circuit open first
        3.times do
          circuit_breaker.call { raise StandardError, 'test error' }
        rescue StandardError
          # Ignore for this test
        end

        # Force to half-open state
        circuit_breaker.half_open!
      end

      it 'closes circuit on successful call' do
        expect(circuit_breaker.state).to eq(:half_open)

        circuit_breaker.call { 'success' }

        expect(circuit_breaker.state).to eq(:closed)
        expect(circuit_breaker.failure_count).to eq(0)
      end

      it 'opens circuit immediately on failure' do
        expect(circuit_breaker.state).to eq(:half_open)

        expect do
          circuit_breaker.call { raise StandardError, 'half-open failure' }
        end.to raise_error(StandardError)

        expect(circuit_breaker.state).to eq(:open)
      end
    end

    context 'when disabled' do
      before do
        allow(ENV).to receive(:[]).with('DISABLE_CIRCUIT_BREAKERS').and_return('true')
      end

      it 'always executes block regardless of state' do
        # Force circuit open
        circuit_breaker.open!

        result = circuit_breaker.call { 'executed despite open circuit' }
        expect(result).to eq('executed despite open circuit')
      end
    end
  end

  describe '#status' do
    it 'returns comprehensive status information' do
      status = circuit_breaker.status

      expect(status).to include(
        name: 'test_service',
        state: :closed,
        failure_count: 0,
        success_count: 0,
        last_failure_time: nil,
        next_attempt_at: nil
      )
    end

    it 'includes next attempt time when circuit is open' do
      # Force circuit open
      circuit_breaker.open!

      status = circuit_breaker.status
      expect(status[:next_attempt_at]).to be_a(Time)
    end
  end

  describe 'manual state control' do
    describe '#open!' do
      it 'manually opens the circuit' do
        circuit_breaker.open!
        expect(circuit_breaker.state).to eq(:open)
      end
    end

    describe '#close!' do
      it 'manually closes the circuit and resets counters' do
        # Create some failures
        begin
          circuit_breaker.call { raise StandardError, 'test error' }
        rescue StandardError
          # Ignore
        end

        circuit_breaker.close!

        expect(circuit_breaker.state).to eq(:closed)
        expect(circuit_breaker.failure_count).to eq(0)
      end
    end

    describe '#half_open!' do
      it 'manually sets circuit to half-open state' do
        circuit_breaker.half_open!
        expect(circuit_breaker.state).to eq(:half_open)
      end
    end
  end
end
