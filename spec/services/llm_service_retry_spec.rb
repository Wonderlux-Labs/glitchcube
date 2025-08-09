# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/llm_service'

RSpec.describe Services::LLMService do
  describe 'retry logic' do
    let(:mock_client) { instance_double(OpenRouter::Client) }
    let(:mock_response) do
      {
        choices: [{ message: { content: 'Test response' } }],
        model: 'test-model',
        usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 }
      }
    end

    before do
      # Mock the LLMService's client method directly
      allow(described_class).to receive(:client).and_return(mock_client)
      allow(Services::CircuitBreakerService).to receive_message_chain(:openrouter_breaker, :call).and_yield
    end

    describe '#with_retry_logic' do
      context 'with retries disabled (default in test)' do
        it 'does not retry on errors', :vcr do
          attempt_count = 0

          expect do
            described_class.send(:with_retry_logic, model: 'test-model', max_attempts: 3) do
              attempt_count += 1
              raise Services::LLMService::RateLimitError, 'Rate limited'
            end
          end.to raise_error(Services::LLMService::RateLimitError)

          # Should only attempt once since retries are disabled in test
          expect(attempt_count).to eq(1)
        end
      end

      context 'with retries enabled' do
        around do |example|
          ENV['ENABLE_RETRIES'] = 'true'
          example.run
          ENV.delete('ENABLE_RETRIES')
        end

        it 'retries on rate limit errors', :vcr do
          attempt_count = 0

          # Don't test sleep implementation details
          allow(described_class).to receive(:sleep)

          expect do
            described_class.send(:with_retry_logic, model: 'test-model', max_attempts: 3) do
              attempt_count += 1
              raise Services::LLMService::RateLimitError, 'Rate limited' if attempt_count < 3

              'success'
            end
          end.not_to raise_error

          expect(attempt_count).to eq(3)
        end
      end

      it 'does not retry authentication errors', :vcr do
        attempt_count = 0

        expect do
          described_class.send(:with_retry_logic, model: 'test-model', max_attempts: 3) do
            attempt_count += 1
            raise Services::LLMService::AuthenticationError, 'Invalid API key'
          end
        end.to raise_error(Services::LLMService::AuthenticationError)

        expect(attempt_count).to eq(1)
      end

      it 'succeeds on first attempt without retries', :vcr do
        attempt_count = 0

        result = described_class.send(:with_retry_logic, model: 'test-model') do
          attempt_count += 1
          'immediate success'
        end

        expect(result).to eq('immediate success')
        expect(attempt_count).to eq(1)
      end

      it 'does not retry in test environment', :vcr do
        attempt_count = 0

        # In test environment, retries are disabled
        expect do
          described_class.send(:with_retry_logic, model: 'test-model') do
            attempt_count += 1
            raise Services::LLMService::LLMError, 'Temporary error'
          end
        end.to raise_error(Services::LLMService::LLMError)

        # Should only attempt once
        expect(attempt_count).to eq(1)
      end
    end

    describe '#complete_with_messages with retry' do
      it 'does not retry in test environment', :vcr do
        call_count = 0

        allow(mock_client).to receive(:complete) do
          call_count += 1
          raise OpenRouter::ServerError, 'Temporary server error'
        end

        # In test environment, retries are disabled
        expect do
          described_class.complete_with_messages(
            messages: [
              { role: 'system', content: 'You are helpful' },
              { role: 'user', content: 'Hello' }
            ]
          )
        end.to raise_error(Services::LLMService::LLMError)

        # Should only attempt once since retries are disabled
        expect(call_count).to eq(1)
      end
    end
  end
end
