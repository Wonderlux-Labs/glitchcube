# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/llm_service'

RSpec.describe Services::LLMService do
  describe 'retry logic' do
    let(:mock_client) { instance_double(::OpenRouter::Client) }
    let(:mock_response) do
      {
        choices: [{ message: { content: 'Test response' } }],
        model: 'test-model',
        usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 }
      }
    end

    before do
      allow(::OpenRouter::Client).to receive(:new).and_return(mock_client)
      allow(Services::CircuitBreakerService).to receive_message_chain(:openrouter_breaker, :call).and_yield
    end

    describe '#with_retry_logic' do
      it 'retries on rate limit errors with exponential backoff' do
        attempt_count = 0
        
        expect(described_class).to receive(:sleep).with(2.0).once
        expect(described_class).to receive(:sleep).with(4.0).once
        
        expect do
          described_class.send(:with_retry_logic, model: 'test-model', max_attempts: 3) do
            attempt_count += 1
            if attempt_count < 3
              raise Services::LLMService::RateLimitError, 'Rate limited'
            else
              'success'
            end
          end
        end.not_to raise_error
        
        expect(attempt_count).to eq(3)
      end

      it 'does not retry authentication errors' do
        attempt_count = 0
        
        expect do
          described_class.send(:with_retry_logic, model: 'test-model', max_attempts: 3) do
            attempt_count += 1
            raise Services::LLMService::AuthenticationError, 'Invalid API key'
          end
        end.to raise_error(Services::LLMService::AuthenticationError)
        
        expect(attempt_count).to eq(1)
      end

      it 'succeeds on first attempt without retries' do
        attempt_count = 0
        
        result = described_class.send(:with_retry_logic, model: 'test-model') do
          attempt_count += 1
          'immediate success'
        end
        
        expect(result).to eq('immediate success')
        expect(attempt_count).to eq(1)
      end

      it 'logs retry attempts' do
        attempt_count = 0
        
        expect(described_class).to receive(:puts).with(/attempt 2\/3/).once
        expect(described_class).to receive(:puts).with(/LLM error - waiting/).once
        expect(described_class).to receive(:puts).with(/succeeded on attempt 2/).once
        expect(described_class).to receive(:sleep).once
        
        described_class.send(:with_retry_logic, model: 'test-model') do
          attempt_count += 1
          if attempt_count == 1
            raise Services::LLMService::LLMError, 'Temporary error'
          else
            'success after retry'
          end
        end
      end
    end

    describe '#complete_with_messages with retry' do
      it 'retries failed API calls' do
        call_count = 0
        
        allow(mock_client).to receive(:complete) do
          call_count += 1
          if call_count == 1
            raise ::OpenRouter::ServerError, 'Temporary server error'
          else
            mock_response
          end
        end
        
        allow(described_class).to receive(:sleep)
        
        result = described_class.complete_with_messages(
          messages: [
            { role: 'system', content: 'You are helpful' },
            { role: 'user', content: 'Hello' }
          ]
        )
        
        expect(result).to be_a(Services::LLMResponse)
        expect(result.content).to eq('Test response')
        expect(call_count).to eq(2)
      end
    end
  end
end