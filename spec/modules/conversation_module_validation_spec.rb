# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/modules/conversation_module'

RSpec.describe ConversationModule do
  let(:conversation_module) { ConversationModule.new }
  let(:mock_persona) do
    double('Persona', generate_fallback_response: 'Fallback response')
  end

  before do
    allow(Services::SimpleLogger).to receive(:warn)
    allow(Services::SimpleLogger).to receive(:debug)
  end

  describe '#validate_response' do
    context 'with valid response data' do
      let(:valid_response) do
        {
          'response' => 'Hello there!',
          'continue_conversation' => true,
          'inner_thoughts' => 'User seems friendly'
        }
      end

      it 'returns the response unchanged when valid' do
        result = conversation_module.send(:validate_response, valid_response, mock_persona)

        expect(result['response']).to eq('Hello there!')
        expect(result['continue_conversation']).to be(true)
        expect(result['inner_thoughts']).to eq('User seems friendly')
      end
    end

    context 'with missing or invalid response text' do
      it 'uses fallback when response is nil' do
        invalid_response = { 'continue_conversation' => false }

        result = conversation_module.send(:validate_response, invalid_response, mock_persona)

        expect(result['response']).to eq('Fallback response')
        expect(Services::SimpleLogger).to have_received(:warn)
          .with('Response text was nil/empty, using fallback', tagged: %i[conversation validation])
      end

      it 'uses fallback when response is empty string' do
        invalid_response = { 'response' => '', 'continue_conversation' => false }

        result = conversation_module.send(:validate_response, invalid_response, mock_persona)

        expect(result['response']).to eq('Fallback response')
        expect(Services::SimpleLogger).to have_received(:warn)
      end

      it 'uses fallback when response is only whitespace' do
        invalid_response = { 'response' => "   \n  \t  ", 'continue_conversation' => false }

        result = conversation_module.send(:validate_response, invalid_response, mock_persona)

        expect(result['response']).to eq('Fallback response')
        expect(Services::SimpleLogger).to have_received(:warn)
      end

      it 'converts non-string response to string' do
        response_with_number = { 'response' => 12_345, 'continue_conversation' => false }

        result = conversation_module.send(:validate_response, response_with_number, mock_persona)

        expect(result['response']).to eq('12345')
      end
    end

    context 'with invalid continue_conversation values' do
      it 'converts string "true" to boolean true' do
        response = { 'response' => 'Hi', 'continue_conversation' => 'true' }

        result = conversation_module.send(:validate_response, response, mock_persona)

        expect(result['continue_conversation']).to be(true)
      end

      it 'converts string "false" to boolean false' do
        response = { 'response' => 'Hi', 'continue_conversation' => 'false' }

        result = conversation_module.send(:validate_response, response, mock_persona)

        expect(result['continue_conversation']).to be(false)
      end

      it 'converts integer 1 to boolean true' do
        response = { 'response' => 'Hi', 'continue_conversation' => 1 }

        result = conversation_module.send(:validate_response, response, mock_persona)

        expect(result['continue_conversation']).to be(true)
      end

      it 'converts integer 0 to boolean false' do
        response = { 'response' => 'Hi', 'continue_conversation' => 0 }

        result = conversation_module.send(:validate_response, response, mock_persona)

        expect(result['continue_conversation']).to be(false)
      end

      it 'defaults to false for nil' do
        response = { 'response' => 'Hi', 'continue_conversation' => nil }

        result = conversation_module.send(:validate_response, response, mock_persona)

        expect(result['continue_conversation']).to be(false)
      end

      it 'defaults to false for unknown values' do
        response = { 'response' => 'Hi', 'continue_conversation' => 'maybe' }

        result = conversation_module.send(:validate_response, response, mock_persona)

        expect(result['continue_conversation']).to be(false)
        expect(Services::SimpleLogger).to have_received(:debug)
          .with('continue_conversation not boolean, defaulting to false',
                hash_including(tagged: %i[conversation validation]))
      end
    end

    context 'with inner_thoughts field' do
      it 'converts non-string inner_thoughts to string' do
        response = { 'response' => 'Hi', 'continue_conversation' => false, 'inner_thoughts' => 123 }

        result = conversation_module.send(:validate_response, response, mock_persona)

        expect(result['inner_thoughts']).to eq('123')
      end

      it 'defaults to empty string when inner_thoughts is nil' do
        response = { 'response' => 'Hi', 'continue_conversation' => false }

        result = conversation_module.send(:validate_response, response, mock_persona)

        expect(result['inner_thoughts']).to eq('')
      end
    end

    context 'with non-hash input' do
      it 'handles non-hash input gracefully' do
        result = conversation_module.send(:validate_response, 'not a hash', mock_persona)

        # String input gets converted to structured format with the string as the response
        expect(result['response']).to eq('not a hash')
        expect(result['continue_conversation']).to be(false)
        expect(result['inner_thoughts']).to eq('')
      end

      it 'handles nil input gracefully' do
        result = conversation_module.send(:validate_response, nil, mock_persona)

        expect(result['response']).to eq('Fallback response')
        expect(result['continue_conversation']).to be(false)
        expect(result['inner_thoughts']).to eq('')
      end
    end

    context 'with very long responses' do
      it 'logs warning for responses over 500 characters' do
        long_response = {
          'response' => 'a' * 600,
          'continue_conversation' => false
        }

        result = conversation_module.send(:validate_response, long_response, mock_persona)

        expect(result['response']).to eq('a' * 600)
        expect(Services::SimpleLogger).to have_received(:warn)
          .with('Response very long, might need truncation',
                tagged: %i[conversation validation],
                length: 600)
      end

      it 'does not log warning for normal length responses' do
        normal_response = {
          'response' => 'This is a normal length response.',
          'continue_conversation' => false
        }

        conversation_module.send(:validate_response, normal_response, mock_persona)

        expect(Services::SimpleLogger).not_to have_received(:warn)
          .with('Response very long, might need truncation', any_args)
      end
    end
  end
end
