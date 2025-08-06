# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/llm_service'
require_relative '../../lib/schemas/conversation_response_schema'

RSpec.describe Services::LLMService, 'structured output support' do
  describe '.complete with structured outputs' do
    context 'with simple structured response' do
      it 'returns JSON matching the schema' do
        schema = GlitchCube::Schemas::ConversationResponseSchema.simple_response
        formatted_schema = GlitchCube::Schemas::ConversationResponseSchema.to_openrouter_format(schema)

        VCR.use_cassette('llm_service_structured_simple', record: :new_episodes) do
          response = described_class.complete(
            system_prompt: 'You are a helpful assistant. Respond in JSON format.',
            user_message: 'Hello, how are you?',
            model: 'google/gemini-2.5-flash',
            temperature: 0.7,
            max_tokens: 150,
            response_format: formatted_schema
          )

          expect(response).to be_a(Services::LLMResponse)
          expect(response.response_text).to be_a(String)
          expect(response.parsed_content).to be_a(Hash)
          expect(response.parsed_content).to have_key('response')
          expect(response.parsed_content).to have_key('continue_conversation')
          expect(response.continue_conversation?).to be_in([true, false])
        end
      end
    end

    context 'with tool calling' do
      let(:tools) do
        [
          {
            type: 'function',
            function: {
              name: 'get_weather',
              description: 'Get the current weather in a location',
              parameters: {
                type: 'object',
                properties: {
                  location: {
                    type: 'string',
                    description: 'The city and state, e.g. San Francisco, CA'
                  }
                },
                required: ['location']
              }
            }
          }
        ]
      end

      it 'calls tools when appropriate' do
        VCR.use_cassette('llm_service_tool_calling', record: :new_episodes) do
          response = described_class.complete(
            system_prompt: 'You are a helpful assistant. Use tools when appropriate.',
            user_message: "What's the weather in San Francisco?",
            model: 'google/gemini-2.5-flash',
            temperature: 0.7,
            max_tokens: 150,
            tools: tools,
            tool_choice: 'auto'
          )

          expect(response).to be_a(Services::LLMResponse)
          expect(response.has_tool_calls?).to be(true)
          expect(response.tool_calls).to be_an(Array)
          expect(response.tool_calls.first).to include(
            id: anything,
            type: 'function',
            function: hash_including(
              name: 'get_weather',
              arguments: be_a(String)
            )
          )

          # Parse the function arguments
          args = response.parse_function_arguments
          expect(args).to be_a(Hash)
          expect(args).to have_key('location')
          expect(args['location']).to include('San Francisco')
        end
      end

      it 'does not call tools when not needed' do
        VCR.use_cassette('llm_service_no_tool_calling', record: :new_episodes) do
          response = described_class.complete(
            system_prompt: 'You are a helpful assistant. Use tools when appropriate.',
            user_message: 'Tell me a joke',
            model: 'google/gemini-2.5-flash',
            temperature: 0.7,
            max_tokens: 150,
            tools: tools,
            tool_choice: 'auto'
          )

          expect(response).to be_a(Services::LLMResponse)
          expect(response.has_tool_calls?).to be(false)
          expect(response.response_text).not_to be_empty
        end
      end
    end

    context 'with conversation continuation' do
      let(:schema) do
        GlitchCube::Schemas::ConversationResponseSchema.to_openrouter_format(
          GlitchCube::Schemas::ConversationResponseSchema.simple_response
        )
      end

      it 'indicates continuation correctly' do
        VCR.use_cassette('llm_service_continue_true', record: :new_episodes) do
          response = described_class.complete(
            system_prompt: 'You are a helpful assistant. Respond in JSON format.',
            user_message: 'Tell me about art',
            model: 'google/gemini-2.5-flash',
            temperature: 0.8,
            max_tokens: 100,
            response_format: schema
          )

          expect(response.continue_conversation?).to be(true)
          expect(response.parsed_content['continue_conversation']).to be(true)
        end
      end

      it 'indicates no continuation correctly' do
        VCR.use_cassette('llm_service_continue_false', record: :new_episodes) do
          response = described_class.complete(
            system_prompt: 'You are a helpful assistant. Respond in JSON format.',
            user_message: 'Goodbye!',
            model: 'google/gemini-2.5-flash',
            temperature: 0.8,
            max_tokens: 100,
            response_format: schema
          )

          expect(response.continue_conversation?).to be(false)
          expect(response.parsed_content['continue_conversation']).to be(false)
        end
      end

      it 'handles edge cases that cause 400 errors' do
        # Test the specific messages that were causing 400 errors
        messages = [
          'What do you think about creativity?',
          "That's all for now, thanks!"
        ]

        messages.each do |msg|
          VCR.use_cassette("llm_service_edge_case_#{msg.gsub(/[^a-z0-9]/i, '_')}", record: :new_episodes) do
            response = described_class.complete(
              system_prompt: 'You are a helpful assistant. Respond in JSON format.',
              user_message: msg,
              model: 'google/gemini-2.5-flash',
              temperature: 0.8,
              max_tokens: 100,
              response_format: schema
            )

            expect(response).to be_a(Services::LLMResponse)
            expect(response.parsed_content).to be_a(Hash)
          rescue Services::LLMService::LLMError => e
            # If we get an error, let's see what it actually is
            puts "Error for message '#{msg}': #{e.message}"
            puts "Error class: #{e.class}"
            raise # Re-raise to fail the test and see the full error
          end
        end
      end
    end
  end
end
