# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::ErrorHandlerService do
  let(:service) { described_class.new }
  let(:error) { StandardError.new('Test error') }
  let(:context) { { service: 'TestService', operation: 'test_operation' } }

  before do
    allow(Services::Logging::SimpleLogger).to receive(:log_api_call)
    allow(GlitchCube.config).to receive(:development?).and_return(false)
    allow(GlitchCube.config).to receive(:redis_url).and_return('redis://localhost:6379/0')
  end

  describe '#handle_error' do
    context 'when self-healing is disabled' do
      before do
        allow(GlitchCube.config).to receive(:self_healing_enabled?).and_return(false)
      end

      it 'logs the error' do
        expect(Services::Logging::SimpleLogger).to receive(:log_api_call).with(
          hash_including(
            service: 'TestService',
            endpoint: 'test_operation',
            error: 'StandardError: Test error'
          )
        )

        service.handle_error(error, context)
      end

      it 'returns the fallback value' do
        result = service.handle_error(error, context.merge(fallback: 'default'))
        expect(result).to eq('default')
      end
    end

    context 'when self-healing is enabled' do
      let(:redis) { instance_double(Redis) }

      before do
        allow(GlitchCube.config).to receive(:self_healing_enabled?).and_return(true)
        allow(GlitchCube.config).to receive(:self_healing_error_threshold).and_return(3)
        allow(Redis).to receive(:new).and_return(redis)
        allow(redis).to receive(:incr).and_return(1)
        allow(redis).to receive(:expire)
        allow(redis).to receive(:exists?).and_return(false)
      end

      it 'tracks error occurrences' do
        expect(redis).to receive(:incr).with(/glitchcube:error_occurrences:/)
        expect(redis).to receive(:expire).with(/glitchcube:error_occurrences:/, 3600)

        service.handle_error(error, context)
      end

      context 'when error threshold is reached' do
        before do
          allow(redis).to receive(:incr).and_return(3)
          allow(Services::System::ErrorHandlingLlm).to receive(:new).and_return(
            instance_double(Services::System::ErrorHandlingLlm, handle_error: true)
          )
        end

        it 'attempts self-healing' do
          llm_handler = instance_double(Services::System::ErrorHandlingLlm)
          expect(Services::System::ErrorHandlingLlm).to receive(:new).and_return(llm_handler)
          expect(llm_handler).to receive(:handle_error).with(error, context)

          service.handle_error(error, context)
        end
      end
    end
  end

  describe '#with_error_handling' do
    context 'when block executes successfully' do
      it 'returns the block result' do
        result = service.with_error_handling('test_op') { 'success' }
        expect(result).to eq('success')
      end
    end

    context 'when block raises an operational error' do
      it 'handles the error and returns fallback' do
        result = service.with_error_handling('test_op', fallback: 'default') do
          raise Services::ErrorHandlerService::NetworkTimeoutError, 'timeout'
        end

        expect(result).to eq('default')
      end

      it 'logs the error as operational' do
        expect(Services::Logging::SimpleLogger).to receive(:log_api_call).with(
          hash_including(operational: true)
        )

        service.with_error_handling('test_op', fallback: 'default') do
          raise Services::ErrorHandlerService::RateLimitError, 'rate limited'
        end
      end
    end

    context 'when block raises an unexpected error' do
      it 're-raises by default' do
        expect do
          service.with_error_handling('test_op') { raise 'unexpected' }
        end.to raise_error(RuntimeError, 'unexpected')
      end

      it 'returns fallback when reraise_unexpected is false' do
        result = service.with_error_handling('test_op', fallback: 'default', reraise_unexpected: false) do
          raise 'unexpected'
        end

        expect(result).to eq('default')
      end
    end
  end

  describe '#with_error_healing' do
    it 'captures caller context' do
      allow(service).to receive(:handle_error).and_call_original

      begin
        service.with_error_healing { raise 'test error' }
      rescue StandardError
        # Expected
      end

      expect(service).to have_received(:handle_error).with(
        anything,
        hash_including(:file, :line, :method, :timestamp)
      )
    end

    it 're-raises the error after handling' do
      expect do
        service.with_error_healing { raise 'test error' }
      end.to raise_error(RuntimeError, 'test error')
    end
  end

  describe 'ErrorHandling module compatibility' do
    let(:test_class) do
      Class.new do
        include ErrorHandling
      end
    end

    let(:test_instance) { test_class.new }

    it 'provides handle_error method' do
      expect(Services::ErrorHandlerService).to receive(:handle_error).with(error, context)
      test_instance.handle_error(error, context)
    end

    it 'provides log_error method' do
      expect(Services::ErrorHandlerService).to receive(:log_error).with(error, context)
      test_instance.log_error(error, context, reraise: false)
    end

    it 'provides with_error_handling method' do
      expect(Services::ErrorHandlerService).to receive(:with_error_handling)
        .with('test_op', fallback: nil, reraise_unexpected: true)
        .and_yield
        .and_return('result')

      result = test_instance.with_error_handling('test_op') { 'result' }
      expect(result).to eq('result')
    end
  end
end
