# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::ConversationResponseProcessor do
  let(:persona_instance) { instance_double(Personas::BasePersona) }
  let(:llm_response) { instance_double(Services::LLMResponse) }
  let(:processor) { described_class.new(llm_response: llm_response, persona_instance: persona_instance) }

  before do
    allow(llm_response).to receive(:cost).and_return(0.001)
    allow(llm_response).to receive(:usage).and_return({ prompt_tokens: 100, completion_tokens: 50 })
    allow(llm_response).to receive(:model).and_return('gpt-4')
    allow(llm_response).to receive(:raw_response).and_return({})
  end

  describe '#process' do
    context 'with complete response data' do
      before do
        allow(llm_response).to receive(:response_text).and_return('Hello there!')
        allow(llm_response).to receive(:continue_conversation?).and_return(true)
        allow(llm_response).to receive(:inner_thoughts).and_return('Thinking about the user')
        allow(llm_response).to receive(:parsed_content).and_return({})
      end

      it 'returns properly formatted response hash' do
        result = processor.process

        expect(result[:response]).to eq('Hello there!')
        expect(result[:continue_conversation]).to be true
        expect(result[:inner_thoughts]).to eq('Thinking about the user')
        expect(result[:cost]).to eq(0.001)
        # with_indifferent_access converts keys to strings
        expect(result[:usage]).to eq({ 'prompt_tokens' => 100, 'completion_tokens' => 50 })
        expect(result[:model]).to eq('gpt-4')
      end

      it 'returns hash with indifferent access' do
        result = processor.process

        expect(result[:response]).to eq('Hello there!')
        expect(result['response']).to eq('Hello there!')
      end
    end

    context 'when response_text is empty' do
      context 'with response in parsed_content' do
        before do
          allow(llm_response).to receive(:response_text).and_return(nil)
          allow(llm_response).to receive(:parsed_content).and_return({ 'response' => 'Parsed response' })
          allow(llm_response).to receive(:continue_conversation?).and_return(false)
          allow(llm_response).to receive(:inner_thoughts).and_return('')
        end

        it 'extracts response from parsed_content' do
          result = processor.process
          expect(result[:response]).to eq('Parsed response')
        end
      end

      context 'with no response anywhere' do
        before do
          allow(llm_response).to receive(:response_text).and_return(nil)
          allow(llm_response).to receive(:parsed_content).and_return({})
          allow(llm_response).to receive(:continue_conversation?).and_return(false)
          allow(llm_response).to receive(:inner_thoughts).and_return('')
          allow(persona_instance).to receive(:generate_fallback_response)
            .with('I understand.')
            .and_return('Fallback response')
          allow(Services::SimpleLogger).to receive(:warn)
        end

        it 'uses persona fallback response' do
          result = processor.process
          expect(result[:response]).to eq('Fallback response')
        end

        it 'logs warning about empty response' do
          expect(Services::SimpleLogger).to receive(:warn)
            .with('Empty response from LLM, using persona fallback')
          processor.process
        end
      end
    end

    context 'when continue_conversation is nil' do
      context 'with value in parsed_content' do
        before do
          allow(llm_response).to receive(:response_text).and_return('Response')
          allow(llm_response).to receive(:continue_conversation?).and_return(nil)
          allow(llm_response).to receive(:parsed_content)
            .and_return({ 'continue_conversation' => true })
          allow(llm_response).to receive(:inner_thoughts).and_return('')
        end

        it 'extracts continue_conversation from parsed_content' do
          result = processor.process
          expect(result[:continue_conversation]).to be true
        end
      end

      context 'with no value anywhere' do
        before do
          allow(llm_response).to receive(:response_text).and_return('Response')
          allow(llm_response).to receive(:continue_conversation?).and_return(nil)
          allow(llm_response).to receive(:parsed_content).and_return({})
          allow(llm_response).to receive(:inner_thoughts).and_return('')
        end

        it 'defaults to false' do
          result = processor.process
          expect(result[:continue_conversation]).to be false
        end
      end
    end

    context 'when inner_thoughts is blank' do
      context 'with value in parsed_content' do
        before do
          allow(llm_response).to receive(:response_text).and_return('Response')
          allow(llm_response).to receive(:continue_conversation?).and_return(false)
          allow(llm_response).to receive(:inner_thoughts).and_return(nil)
          allow(llm_response).to receive(:parsed_content)
            .and_return({ 'inner_thoughts' => 'Deep thinking' })
        end

        it 'extracts inner_thoughts from parsed_content' do
          result = processor.process
          expect(result[:inner_thoughts]).to eq('Deep thinking')
        end
      end

      context 'with no value anywhere' do
        before do
          allow(llm_response).to receive(:response_text).and_return('Response')
          allow(llm_response).to receive(:continue_conversation?).and_return(false)
          allow(llm_response).to receive(:inner_thoughts).and_return(nil)
          allow(llm_response).to receive(:parsed_content).and_return({})
        end

        it 'defaults to empty string' do
          result = processor.process
          expect(result[:inner_thoughts]).to eq('')
        end
      end
    end

    context 'with symbol keys in parsed_content' do
      before do
        allow(llm_response).to receive(:response_text).and_return(nil)
        allow(llm_response).to receive(:continue_conversation?).and_return(nil)
        allow(llm_response).to receive(:inner_thoughts).and_return(nil)
        allow(llm_response).to receive(:parsed_content).and_return({
                                                                     response: 'Symbol response',
                                                                     continue_conversation: true,
                                                                     inner_thoughts: 'Symbol thoughts'
                                                                   })
      end

      it 'handles symbol keys properly' do
        result = processor.process
        expect(result[:response]).to eq('Symbol response')
        expect(result[:continue_conversation]).to be true
        expect(result[:inner_thoughts]).to eq('Symbol thoughts')
      end
    end
  end
end
