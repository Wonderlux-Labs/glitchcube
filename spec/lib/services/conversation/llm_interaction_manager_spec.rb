# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::Conversation::LlmInteractionManager do
  include_context 'with_full_conversation_setup'

  subject { described_class.new }

  let(:conversation_history) do
    [
      { role: 'user', content: 'Hello' },
      { role: 'assistant', content: 'Hi there!' }
    ]
  end
  let(:system_prompt) { 'You are a helpful assistant.' }
  let(:user_message) { 'What is the meaning of life?' }
  let(:context) { { session_id: 'test-session', persona: 'buddy' } }

  describe '#prepare_messages' do
    it 'prepares messages in correct format' do
      result = subject.prepare_messages(conversation_history, system_prompt, user_message)

      expect(result).to be_an(Array)
      expect(result.first[:role]).to eq('system')
      expect(result.last[:role]).to eq('user')
      expect(result.last[:content]).to eq(user_message)
    end

    it 'includes conversation history' do
      result = subject.prepare_messages(conversation_history, system_prompt, user_message)

      expect(result.length).to eq(4) # system + 2 history + user
    end

    it 'handles empty conversation history' do
      result = subject.prepare_messages([], system_prompt, user_message)

      expect(result.length).to eq(2) # system + user
      expect(result.first[:role]).to eq('system')
      expect(result.last[:role]).to eq('user')
    end
  end

  describe '#call_llm' do
    let(:messages) { subject.prepare_messages(conversation_history, system_prompt, user_message) }
    let(:llm_options) { { model: 'gpt-3.5-turbo' } }

    it 'calls LLM service successfully' do
      expect { subject.call_llm(messages: messages, llm_options: llm_options, session_id: 'test') }.not_to raise_error
    end

    it 'logs LLM interaction start' do
      subject.call_llm(messages: messages, llm_options: llm_options, session_id: 'test')

      expect(Services::Logging::SimpleLogger).to have_received(:info)
        .with(match(/Calling LLM/), hash_including(tagged: include(:conversation, :llm)))
    end

    it 'handles different LLM options' do
      custom_options = { model: 'gpt-4', temperature: 0.8 }

      expect { subject.call_llm(messages: messages, llm_options: custom_options) }.not_to raise_error
    end
  end

  describe '#build_system_prompt' do
    let(:persona_instance) { instance_double('PersonaInstance', name: 'buddy', generate_system_prompt: 'Base prompt') }

    before do
      allow(Services::Memory::ContextInjectionService).to receive(:inject_context).and_return('Enhanced prompt')
    end

    it 'builds system prompt successfully' do
      result = subject.build_system_prompt(persona_instance, context)

      expect(result).to be_a(String)
      expect(result).not_to be_empty
    end

    it 'enriches context appropriately' do
      subject.build_system_prompt(persona_instance, context)

      expect(Services::Memory::ContextInjectionService).to have_received(:inject_context)
        .with('Base prompt', hash_including(:current_persona, :session_id))
    end

    it 'adds JSON instruction when no tools' do
      result = subject.build_system_prompt(persona_instance, context)

      expect(result).to include('JSON')
    end

    it 'logs prompt generation' do
      subject.build_system_prompt(persona_instance, context)

      expect(Services::Logging::SimpleLogger).to have_received(:debug)
        .with(match(/System prompt generated/), hash_including(tagged: include(:conversation, :prompt)))
    end
  end

  describe '#select_appropriate_model' do
    it 'selects default model for normal context' do
      result = subject.select_appropriate_model(context, 'test-session')

      expect(result).to be_a(String)
    end

    it 'selects tools model when tools present' do
      tools_context = context.merge(tools: [{ type: 'function', function: { name: 'test' } }])

      result = subject.select_appropriate_model(tools_context, 'test-session')

      expect(result).to be_a(String)
    end

    it 'logs model selection' do
      subject.select_appropriate_model(context, 'test-session')

      expect(Services::Logging::SimpleLogger).to have_received(:debug)
        .with(match(/Selected model/), hash_including(tagged: include(:conversation, :llm)))
    end
  end

  describe '#get_response_schema' do
    it 'returns nil when schema not defined' do
      result = subject.get_response_schema(context)

      expect(result).to be_nil
    end

    it 'handles different context types' do
      image_context = context.merge(image_analysis: true)
      tools_context = context.merge(tools: [{ type: 'function' }])
      simple_context = context.merge(simple_mode: true)

      expect { subject.get_response_schema(image_context) }.not_to raise_error
      expect { subject.get_response_schema(tools_context) }.not_to raise_error
      expect { subject.get_response_schema(simple_context) }.not_to raise_error
    end
  end

  describe 'integration behavior' do
    let(:persona_instance) { instance_double('PersonaInstance', name: 'buddy', generate_system_prompt: 'Base prompt') }

    before do
      allow(Services::Memory::ContextInjectionService).to receive(:inject_context).and_return('Enhanced prompt')
    end

    it 'coordinates between all methods' do
      messages = subject.prepare_messages(conversation_history, system_prompt, user_message)
      model = subject.select_appropriate_model(context, 'test')
      system_prompt_result = subject.build_system_prompt(persona_instance, context)

      expect(messages).to be_an(Array)
      expect(model).to be_a(String)
      expect(system_prompt_result).to be_a(String)
    end

    it 'maintains consistent logging' do
      subject.select_appropriate_model(context, 'test')
      subject.build_system_prompt(persona_instance, context)

      expect(Services::Logging::SimpleLogger).to have_received(:debug).at_least(:twice)
    end
  end
end
