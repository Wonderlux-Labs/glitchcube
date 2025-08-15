# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::Llm::LLMResponse, 'JSON parsing fix' do
  describe '#response_text' do
    context 'with mixed format response (text + JSON)' do
      it 'extracts response from JSON when content includes extra text' do
        # Simulate the production issue: " successfully\n\n{\"response\": \"...\", ...}"
        content = " successfully\n\n{\"response\": \"OH FUCK YES! Red lights coming right the hell up!\", \"continue_conversation\": true}"

        response_data = {
          content: content,
          model: 'anthropic/claude-sonnet-4',
          usage: { prompt_tokens: 100, completion_tokens: 50 }
        }

        llm_response = described_class.new(response_data)

        # Should extract just the response field from the JSON
        expect(llm_response.response_text).to eq('OH FUCK YES! Red lights coming right the hell up!')
      end

      it 'handles invalid JSON gracefully' do
        # Content with invalid JSON should return the original content
        content = " successfully\n\n{\"response\": \"incomplete json"

        response_data = {
          content: content,
          model: 'anthropic/claude-sonnet-4',
          usage: { prompt_tokens: 100, completion_tokens: 50 }
        }

        llm_response = described_class.new(response_data)

        # Should return original content when JSON parsing fails
        expect(llm_response.response_text).to eq(content)
      end

      it 'works with clean JSON responses' do
        # Clean JSON response should still work
        content = '{"response": "Clean JSON response", "continue_conversation": true}'

        response_data = {
          content: content,
          model: 'anthropic/claude-sonnet-4',
          usage: { prompt_tokens: 100, completion_tokens: 50 }
        }

        llm_response = described_class.new(response_data)

        # Should extract the response field
        expect(llm_response.response_text).to eq('Clean JSON response')
      end

      it 'returns plain text for non-JSON responses' do
        # Plain text response should be returned as-is
        content = 'This is just plain text with no JSON'

        response_data = {
          content: content,
          model: 'anthropic/claude-sonnet-4',
          usage: { prompt_tokens: 100, completion_tokens: 50 }
        }

        llm_response = described_class.new(response_data)

        # Should return the plain text
        expect(llm_response.response_text).to eq(content)
      end
    end
  end
end
