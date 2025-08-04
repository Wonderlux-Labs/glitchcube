# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::CircuitBreakerService do
  describe '.home_assistant_breaker' do
    it 'returns a circuit breaker for home assistant' do
      breaker = described_class.home_assistant_breaker
      expect(breaker).to be_a(CircuitBreaker)
      expect(breaker.name).to eq('home_assistant')
    end

    it 'returns the same instance on multiple calls' do
      breaker1 = described_class.home_assistant_breaker
      breaker2 = described_class.home_assistant_breaker
      expect(breaker1).to be(breaker2)
    end
  end

  describe '.openrouter_breaker' do
    it 'returns a circuit breaker for openrouter' do
      breaker = described_class.openrouter_breaker
      expect(breaker).to be_a(CircuitBreaker)
      expect(breaker.name).to eq('openrouter')
    end

    it 'returns the same instance on multiple calls' do
      breaker1 = described_class.openrouter_breaker
      breaker2 = described_class.openrouter_breaker
      expect(breaker1).to be(breaker2)
    end
  end

  describe '.all_breakers' do
    it 'returns all circuit breakers' do
      breakers = described_class.all_breakers
      expect(breakers).to contain_exactly(
        described_class.home_assistant_breaker,
        described_class.openrouter_breaker
      )
    end
  end

  describe '.status' do
    it 'returns status for all breakers' do
      status = described_class.status
      expect(status).to be_an(Array)
      expect(status.length).to eq(2)
      
      status.each do |breaker_status|
        expect(breaker_status).to include(:name, :state, :failure_count)
      end
    end
  end

  describe '.reset_all' do
    it 'calls close! on all breakers' do
      ha_breaker = described_class.home_assistant_breaker
      or_breaker = described_class.openrouter_breaker

      allow(ha_breaker).to receive(:close!)
      allow(or_breaker).to receive(:close!)

      described_class.reset_all

      expect(ha_breaker).to have_received(:close!)
      expect(or_breaker).to have_received(:close!)
    end
  end
end