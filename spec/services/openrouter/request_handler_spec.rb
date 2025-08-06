# frozen_string_literal: true

require 'spec_helper'
require 'services/openrouter/request_handler'

RSpec.describe Services::OpenRouter::RequestHandler do
  let(:client) { double('OpenRouter::Client') }
  let(:handler) { described_class.new(client) }
  let(:request_params) do
    {
      model: 'test-model',
      messages: [{ role: 'user', content: 'Hello world' }],
      temperature: 0.7,
      max_tokens: 100
    }
  end

  describe '#make_api_call' do
    context 'when API call succeeds' do
      let(:response) do
        {
          'choices' => [
            { 'message' => { 'content' => 'Hello there!' } }
          ],
          'usage' => {
            'prompt_tokens' => 10,
            'completion_tokens' => 5,
            'total_tokens' => 15
          }
        }
      end

      before do
        allow(client).to receive(:complete).with(request_params).and_return(response)
      end

      it 'returns the API response' do
        result = handler.make_api_call(request_params)
        expect(result).to eq(response)
      end

      it 'logs the successful API call', :pending do
        expect(Services::LoggerService).to receive(:log_api_call).with(
          hash_including(
            service: 'openrouter',
            endpoint: 'chat/completions',
            method: 'POST',
            status: 200,
            model: 'test-model',
            temperature: 0.7,
            max_tokens: 100,
            tokens_used: {
              prompt_tokens: 10,
              completion_tokens: 5,
              total_tokens: 15
            }
          )
        )

        handler.make_api_call(request_params)
      end
    end

    context 'when API call fails' do
      let(:error) { StandardError.new('API Error') }

      before do
        allow(client).to receive(:complete).with(request_params).and_raise(error)
      end

      it 'raises the error' do
        expect { handler.make_api_call(request_params) }.to raise_error(StandardError, 'API Error')
      end

      it 'logs the failed API call', :pending do
        expect(Services::LoggerService).to receive(:log_api_call).with(
          hash_including(
            service: 'openrouter',
            endpoint: 'chat/completions',
            method: 'POST',
            status: 500,
            error: 'API Error',
            model: 'test-model',
            temperature: 0.7,
            max_tokens: 100
          )
        )

        expect { handler.make_api_call(request_params) }.to raise_error(StandardError)
      end
    end

    context 'when response has no usage data' do
      let(:response) do
        {
          'choices' => [
            { 'message' => { 'content' => 'Hello there!' } }
          ]
        }
      end

      before do
        allow(client).to receive(:complete).with(request_params).and_return(response)
      end

      it 'logs with nil token usage', :pending do
        expect(Services::LoggerService).to receive(:log_api_call).with(
          hash_including(
            tokens_used: nil
          )
        )

        handler.make_api_call(request_params)
      end
    end
  end
end
