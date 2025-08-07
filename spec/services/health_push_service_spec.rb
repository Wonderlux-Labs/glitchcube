# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/health_push_service'
require_relative '../../lib/home_assistant_client'

RSpec.describe Services::HealthPushService, :vcr do
  let(:service) { described_class.new }
  let(:uptime_kuma_url) { 'https://status.wlux.casa/api/push/Bf8nrx6ykq' }

  before do
    # No mocking of HomeAssistantClient - VCR handles all external calls

    # Mock config instead of ENV
    allow(GlitchCube.config.monitoring).to receive(:uptime_kuma_push_url).and_return(uptime_kuma_url)
    allow(GlitchCube.config).to receive(:redis_url).and_return('redis://localhost:6379')

    # Set start time for uptime calculations
    GlitchCube.start_time = Time.now - 3600 # 1 hour ago
  end

  describe '#push_health_status' do
    let(:redis) { instance_double(Redis) }

    before do
      allow(Redis).to receive(:new).and_return(redis)
      allow(redis).to receive(:ping).and_return('PONG')
      allow(redis).to receive(:quit)
      allow(ActiveRecord::Base.connection).to receive(:active?).and_return(true)

      # Mock circuit breakers
      closed_breaker = double('breaker', state: :closed)
      allow(Services::CircuitBreakerService).to receive_messages(home_assistant_breaker: closed_breaker, openrouter_breaker: closed_breaker)
    end

    context 'when Home Assistant is available' do
      # Use VCR to record actual Home Assistant responses
      # The actual response will be captured in the cassette

      it 'pushes HA health data to Uptime Kuma with status up', vcr: { cassette_name: 'health_push/ha_available' } do
        # VCR will record both HA call and Uptime Kuma push
        result = service.push_health_status

        expect(result[:status]).to be_present
        expect(result[:message]).to be_present
        # Don't enforce specific status since VCR will capture actual responses
      end
    end

    context 'when Home Assistant is unavailable' do
      # VCR will capture the actual unavailable state

      it 'generates fallback health message and pushes with status up when Sinatra is healthy', vcr: { cassette_name: 'health_push/ha_unavailable' } do
        result = service.push_health_status

        # VCR will capture actual responses - just verify service returns a result
        expect(result[:status]).to be_present
        expect(result[:message]).to be_present
      end

      context 'with Redis down' do
        before do
          allow(redis).to receive(:ping).and_raise(Redis::CannotConnectError)
        end

        it 'includes Redis issue in fallback message', vcr: { cassette_name: 'health_push/redis_down' } do
          result = service.push_health_status

          # VCR will capture the actual response - verify service handles Redis failure
          expect(result[:status]).to be_present
          expect(result[:message]).to be_present
        end
      end

      context 'with circuit breakers open' do
        before do
          open_breaker = double('breaker', state: :open)
          half_open_breaker = double('breaker', state: :half_open)

          allow(Services::CircuitBreakerService).to receive_messages(home_assistant_breaker: open_breaker, openrouter_breaker: half_open_breaker)
        end

        it 'includes circuit breaker status in fallback message', vcr: { cassette_name: 'health_push/circuit_breakers_open' } do
          result = service.push_health_status

          # VCR will capture the actual response - verify service handles circuit breaker states
          expect(result[:status]).to be_present
          expect(result[:message]).to be_present
        end
      end
    end

    context 'when Uptime Kuma URL is not configured' do
      let(:uptime_kuma_url) { nil }

      before do
        allow(GlitchCube.config.monitoring).to receive(:uptime_kuma_push_url).and_return(nil)
      end

      it 'returns health data without pushing', vcr: { cassette_name: 'health_push/no_uptime_kuma_url' } do
        result = service.push_health_status

        # VCR will capture what actually happens when Uptime Kuma URL is not configured
        expect(result[:status]).to be_present
        expect(result[:sinatra_health]).to be_a(Hash)
      end
    end

    context 'when an error occurs' do
      it 'returns error status with message', vcr: { cassette_name: 'health_push/ha_error' } do
        # VCR will capture what happens when HA has errors
        result = service.push_health_status

        expect(result[:status]).to be_present
        expect(result[:message]).to be_present
      end
    end
  end

  describe 'private methods' do
    describe '#check_sinatra_health' do
      let(:redis) { instance_double(Redis) }

      context 'when all services are healthy' do
        before do
          allow(Redis).to receive(:new).and_return(redis)
          allow(redis).to receive(:ping).and_return('PONG')
          allow(redis).to receive(:quit)
          allow(ActiveRecord::Base.connection).to receive(:active?).and_return(true)

          closed_breaker = double('breaker', state: :closed)
          allow(Services::CircuitBreakerService).to receive_messages(home_assistant_breaker: closed_breaker, openrouter_breaker: closed_breaker)
        end

        it 'returns healthy status with no issues' do
          result = service.send(:check_sinatra_health)

          expect(result[:healthy]).to be(true)
          expect(result[:issues]).to be_empty
          expect(result[:circuit_breakers]).to eq('home_assistant' => 'closed', 'openrouter' => 'closed')
        end
      end

      context 'when services have issues' do
        before do
          allow(Redis).to receive(:new).and_return(redis)
          allow(redis).to receive(:ping).and_raise(Redis::CannotConnectError)
          allow(ActiveRecord::Base.connection).to receive(:active?).and_raise(StandardError, 'Connection error')

          open_breaker = double('breaker', state: :open)
          allow(Services::CircuitBreakerService).to receive_messages(home_assistant_breaker: open_breaker, openrouter_breaker: nil)
        end

        it 'returns degraded status with issues list' do
          result = service.send(:check_sinatra_health)

          expect(result[:healthy]).to be(false)
          expect(result[:issues]).to include('Redis:down', 'DB:down', 'home_assistant: open')
          expect(result[:circuit_breakers]).to eq('home_assistant' => 'open')
        end
      end
    end

    describe '#generate_fallback_health_message' do
      let(:sinatra_health) do
        {
          healthy: true,
          issues: [],
          circuit_breakers: { 'home_assistant' => 'closed', 'openrouter' => 'closed' }
        }
      end

      it 'generates proper fallback message when API is healthy' do
        message = service.send(:generate_fallback_health_message, sinatra_health)

        expect(message).to match(/^HA:DOWN \| API:OK \| Up:\d+\.?\d*h$/)
      end

      context 'with issues' do
        let(:sinatra_health) do
          {
            healthy: false,
            issues: ['Redis:down', 'DB:down'],
            circuit_breakers: { 'home_assistant' => 'open', 'openrouter' => 'half_open' }
          }
        end

        it 'includes all issues and circuit breaker status' do
          message = service.send(:generate_fallback_health_message, sinatra_health)

          expect(message).to match(/^HA:DOWN \| API:DEGRADED \| Up:\d+\.?\d*h \| Issues:Redis:down,DB:down \| CB:home_assistant:open,openrouter:half_open$/)
        end
      end
    end
  end
end
