# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/modules/conversation_module'
require 'active_support/core_ext/hash/indifferent_access'

RSpec.describe ConversationModule do
  let(:conversation_module) { ConversationModule.new }
  let(:mock_persona) do
    double('Persona', generate_fallback_response: 'Fallback response')
  end

  before do
    allow(Services::SimpleLogger).to receive(:warn)
    allow(Services::SimpleLogger).to receive(:debug)
    allow(Services::SimpleLogger).to receive(:info)
  end

  # Helper method to create mock LLMResponse objects
  def mock_llm_response(content, parsed_content = nil)
    double('LLMResponse',
           content: content,
           parsed_content: parsed_content&.with_indifferent_access)
  end

  describe '#validate_response' do
    context 'with valid response data' do
      let(:valid_response_data) do
        {
          'response' => 'Hello there!',
          'continue_conversation' => true,
          'inner_thoughts' => 'User seems friendly'
        }
      end

      let(:valid_response) { mock_llm_response('Hello there!', valid_response_data) }

      it 'returns the response unchanged when valid' do
        result = conversation_module.send(:validate_response, valid_response, mock_persona)

        expect(result['response']).to eq('Hello there!')
        expect(result['continue_conversation']).to be(true)
        expect(result['inner_thoughts']).to eq('User seems friendly')
      end
    end

    context 'with missing or invalid response text' do
      it 'uses fallback when response is nil' do
        invalid_response_data = { 'continue_conversation' => false }
        invalid_response = mock_llm_response(nil, invalid_response_data)

        result = conversation_module.send(:validate_response, invalid_response, mock_persona)

        expect(result['response']).to eq('Fallback response')
        expect(Services::SimpleLogger).to have_received(:warn)
          .with('Response text was nil/empty, using fallback', tagged: %i[conversation validation])
      end

      it 'uses fallback when response is empty string' do
        invalid_response_data = { 'response' => '', 'continue_conversation' => false }
        invalid_response = mock_llm_response('', invalid_response_data)

        result = conversation_module.send(:validate_response, invalid_response, mock_persona)

        expect(result['response']).to eq('Fallback response')
        expect(Services::SimpleLogger).to have_received(:warn)
      end

      it 'uses fallback when response is only whitespace' do
        invalid_response_data = { 'response' => "   \n  \t  ", 'continue_conversation' => false }
        invalid_response = mock_llm_response("   \n  \t  ", invalid_response_data)

        result = conversation_module.send(:validate_response, invalid_response, mock_persona)

        expect(result['response']).to eq('Fallback response')
        expect(Services::SimpleLogger).to have_received(:warn)
      end

      it 'converts non-string response to string' do
        response_data = { 'response' => 12_345, 'continue_conversation' => false }
        response_with_number = mock_llm_response('12345', response_data)

        result = conversation_module.send(:validate_response, response_with_number, mock_persona)

        expect(result['response']).to eq('12345')
      end
    end

    context 'with invalid continue_conversation values' do
      it 'converts string "true" to boolean true' do
        response_data = { 'response' => 'Hi', 'continue_conversation' => 'true' }
        response = mock_llm_response('Hi', response_data)

        result = conversation_module.send(:validate_response, response, mock_persona)

        expect(result['continue_conversation']).to be(true)
      end

      it 'converts string "false" to boolean false' do
        response_data = { 'response' => 'Hi', 'continue_conversation' => 'false' }
        response = mock_llm_response('Hi', response_data)

        result = conversation_module.send(:validate_response, response, mock_persona)

        expect(result['continue_conversation']).to be(false)
      end

      it 'converts integer 1 to boolean true' do
        response_data = { 'response' => 'Hi', 'continue_conversation' => 1 }
        response = mock_llm_response('Hi', response_data)

        result = conversation_module.send(:validate_response, response, mock_persona)

        expect(result['continue_conversation']).to be(true)
      end

      it 'converts integer 0 to boolean false' do
        response_data = { 'response' => 'Hi', 'continue_conversation' => 0 }
        response = mock_llm_response('Hi', response_data)

        result = conversation_module.send(:validate_response, response, mock_persona)

        expect(result['continue_conversation']).to be(false)
      end

      it 'defaults to false for nil' do
        response_data = { 'response' => 'Hi', 'continue_conversation' => nil }
        response = mock_llm_response('Hi', response_data)

        result = conversation_module.send(:validate_response, response, mock_persona)

        expect(result['continue_conversation']).to be(false)
      end

      it 'defaults to false for unknown values' do
        response_data = { 'response' => 'Hi', 'continue_conversation' => 'maybe' }
        response = mock_llm_response('Hi', response_data)

        result = conversation_module.send(:validate_response, response, mock_persona)

        expect(result['continue_conversation']).to be(false)
        # The simplified code no longer logs this specific debug message
        # It just coerces to false silently
      end
    end

    context 'with inner_thoughts field' do
      it 'converts non-string inner_thoughts to string' do
        response_data = { 'response' => 'Hi', 'continue_conversation' => false, 'inner_thoughts' => 123 }
        response = mock_llm_response('Hi', response_data)

        result = conversation_module.send(:validate_response, response, mock_persona)

        expect(result['inner_thoughts']).to eq('123')
      end

      it 'defaults to empty string when inner_thoughts is nil' do
        response_data = { 'response' => 'Hi', 'continue_conversation' => false }
        response = mock_llm_response('Hi', response_data)

        result = conversation_module.send(:validate_response, response, mock_persona)

        expect(result['inner_thoughts']).to eq('')
      end
    end

    context 'with non-hash input' do
      it 'handles non-hash input gracefully' do
        # When parsed_content is nil, it should fall back to using the raw content
        response = mock_llm_response('not a hash', nil)

        result = conversation_module.send(:validate_response, response, mock_persona)

        # String input gets converted to structured format with the string as the response
        expect(result['response']).to eq('not a hash')
        expect(result['continue_conversation']).to be(false)
        expect(result['inner_thoughts']).to eq('')
      end

      it 'handles nil input gracefully' do
        # When both content and parsed_content are nil, should use fallback
        response = mock_llm_response(nil, nil)

        result = conversation_module.send(:validate_response, response, mock_persona)

        expect(result['response']).to eq('Fallback response')
        expect(result['continue_conversation']).to be(false)
        expect(result['inner_thoughts']).to eq('')
      end
    end

    context 'with very long responses' do
      it 'logs warning for responses over 500 characters' do
        long_response_data = {
          'response' => 'a' * 600,
          'continue_conversation' => false
        }
        long_response = mock_llm_response('a' * 600, long_response_data)

        result = conversation_module.send(:validate_response, long_response, mock_persona)

        expect(result['response']).to eq('a' * 600)
        expect(Services::SimpleLogger).to have_received(:warn)
          .with('Response very long, might need truncation',
                tagged: %i[conversation validation],
                length: 600)
      end

      it 'does not log warning for normal length responses' do
        normal_response_data = {
          'response' => 'This is a normal length response.',
          'continue_conversation' => false
        }
        normal_response = mock_llm_response('This is a normal length response.', normal_response_data)

        conversation_module.send(:validate_response, normal_response, mock_persona)

        expect(Services::SimpleLogger).not_to have_received(:warn)
          .with('Response very long, might need truncation', any_args)
      end
    end
  end
end
