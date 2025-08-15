# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::Llm::Components::ErrorHandler do
  describe '.handle_error' do
    context 'with 400 client error containing response body' do
      it 'logs the full response body for debugging' do
        # Create a mock Faraday error with response body like OpenRouter would return
        error_response = {
          status: 400,
          body: '{"error": {"message": "anthropic-claude-sonnet-4 is not a valid model ID", "code": 400}}'
        }

        faraday_error = Faraday::BadRequestError.new('the server responded with status 400')
        allow(faraday_error).to receive(:response).and_return(error_response)

        # Expect the debug dump to be logged first
        expect(Services::Logging::SimpleLogger).to receive(:debug).with(
          'RAW ERROR DUMP',
          tagged: %i[llm error_debug],
          raw_error_info: include('API Response: {"error": {"message": "anthropic-claude-sonnet-4 is not a valid model ID", "code": 400}}')
        )

        # Expect the error response body to be logged
        expect(Services::Logging::SimpleLogger).to receive(:error).with(
          'LLM API ERROR RESPONSE BODY',
          tagged: %i[llm error_response],
          status: 400,
          response_body: '{"error": {"message": "anthropic-claude-sonnet-4 is not a valid model ID", "code": 400}}'
        )

        # Should raise an LLMError with the actual API error message
        expect do
          described_class.handle_error(faraday_error)
        end.to raise_error(Services::Llm::LLMService::LLMError, /anthropic-claude-sonnet-4 is not a valid model ID/)
      end

      it 'falls back to error.inspect when JSON parsing fails' do
        # Create error with invalid JSON response body
        error_response = {
          status: 400,
          body: 'invalid json response'
        }

        faraday_error = Faraday::BadRequestError.new('the server responded with status 400')
        allow(faraday_error).to receive(:response).and_return(error_response)

        # Allow logging calls so they don't interfere with the test
        allow(Services::Logging::SimpleLogger).to receive(:debug)
        allow(Services::Logging::SimpleLogger).to receive(:error)

        # Should raise an LLMError using error.inspect as fallback
        expect do
          described_class.handle_error(faraday_error)
        end.to raise_error(Services::Llm::LLMService::LLMError) do |error|
          expect(error.message).to include('400')
          expect(error.message).to include('Faraday::BadRequestError') # From error.inspect
        end

        # Verify the debug dump was called
        expect(Services::Logging::SimpleLogger).to have_received(:debug).with(
          'RAW ERROR DUMP',
          tagged: %i[llm error_debug],
          raw_error_info: include('API Response: invalid json response')
        )

        # Verify the error response body was logged
        expect(Services::Logging::SimpleLogger).to have_received(:error).with(
          'LLM API ERROR RESPONSE BODY',
          tagged: %i[llm error_response],
          status: 400,
          response_body: 'invalid json response'
        )
      end
    end
  end
end
