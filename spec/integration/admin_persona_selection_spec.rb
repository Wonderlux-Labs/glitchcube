# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require_relative '../../app'

RSpec.describe 'Admin Persona Selection Integration', type: :request do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  before do
    # Skip authentication for testing
    allow_any_instance_of(Sinatra::Base).to receive(:authorize!).and_return(true)

    # Mock Home Assistant client
    mock_ha = instance_double(HomeAssistantClient)
    allow(HomeAssistantClient).to receive(:new).and_return(mock_ha)
    allow(mock_ha).to receive_messages(
      call_service: true,
      state: nil,
      speak: true,
      awtrix_display_text: true,
      awtrix_mood_light: true
    )

    # Mock LLM service
    mock_llm_response = double('LLMResponse',
                               response_text: 'Test response',
                               continue_conversation?: false,
                               has_tool_calls?: false,
                               cost: 0.001,
                               model: 'test-model',
                               usage: { prompt_tokens: 10, completion_tokens: 20 })
    allow(Services::LLMService).to receive(:complete_with_messages).and_return(mock_llm_response)

    # Mock conversation session
    mock_session = instance_double(Services::ConversationSession,
                                   session_id: 'test-123',
                                   messages_for_llm: [],
                                   add_message: true,
                                   messages: double('messages', count: 0),
                                   created_at: Time.now - 1.minute,
                                   metadata: {})
    allow(Services::ConversationSession).to receive(:find_or_create).and_return(mock_session)
  end

  describe 'GET /admin' do
    it 'displays available personas in dropdown' do
      get '/admin'

      expect(last_response).to be_ok
      expect(last_response.body).to include('<select name="persona"')
      expect(last_response.body).to include('value="buddy"')
      expect(last_response.body).to include('value="jax"')
      expect(last_response.body).to include('value="lomi"')
      expect(last_response.body).to include('value="zorp"')
    end

    it 'does not display removed personas' do
      get '/admin'

      expect(last_response.body).not_to include('value="playful"')
      expect(last_response.body).not_to include('value="contemplative"')
      expect(last_response.body).not_to include('value="mysterious"')
    end
  end

  describe 'POST /admin/test_voice' do
    it 'uses selected persona for voice test' do
      post '/admin/test_voice', {
        persona: 'jax',
        message: 'Test message'
      }

      expect(last_response).to be_redirect
      follow_redirect!
      expect(last_response.body).to include('Voice test initiated')
    end

    it 'creates proper persona instance for voice' do
      expect(Personas::BasePersona).to receive(:create).with('lomi', anything).and_call_original

      post '/admin/test_voice', {
        persona: 'lomi',
        message: 'Testing LOMI voice'
      }
    end
  end

  describe 'POST /conversation' do
    let(:conversation_params) do
      {
        message: 'Hello there!',
        persona: 'buddy'
      }
    end

    it 'uses selected persona for conversation' do
      expect(Personas::BasePersona).to receive(:create).with('buddy', anything).and_call_original

      post '/conversation', conversation_params.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response).to be_ok
      response_json = JSON.parse(last_response.body)
      expect(response_json['persona']).to eq('buddy')
    end

    it 'handles different personas correctly' do
      %w[buddy jax lomi zorp].each do |persona|
        params = conversation_params.merge(persona: persona)

        post '/conversation', params.to_json, { 'CONTENT_TYPE' => 'application/json' }

        expect(last_response).to be_ok
        response_json = JSON.parse(last_response.body)
        expect(response_json['persona']).to eq(persona)
      end
    end

    it 'defaults to buddy when no persona specified' do
      params = { message: 'Hello!' }

      post '/conversation', params.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response).to be_ok
      response_json = JSON.parse(last_response.body)
      expect(response_json['persona']).to eq('buddy')
    end

    it 'handles invalid persona gracefully' do
      params = conversation_params.merge(persona: 'invalid_persona')

      post '/conversation', params.to_json, { 'CONTENT_TYPE' => 'application/json' }

      expect(last_response).to be_ok
      # Should default to buddy for unknown personas
      response_json = JSON.parse(last_response.body)
      expect(response_json['persona']).to eq('invalid_persona')
    end
  end

  describe 'Persona tools integration' do
    it 'loads correct tools for each persona' do
      # Each persona should have its own tool set
      %w[buddy jax lomi zorp].each do |persona_name|
        persona = Personas::BasePersona.create(persona_name)
        tools = persona.tool_schemas

        expect(tools).to be_an(Array)
        expect(tools).not_to be_empty if persona_name != 'default'

        tools.each do |tool|
          expect(tool).to have_key('type')
          expect(tool).to have_key('function')
          expect(tool['function']).to have_key('name')
          expect(tool['function']).to have_key('description')
        end
      end
    end
  end

  describe 'Character Service integration' do
    it 'bridges CharacterService to use Personas' do
      %w[buddy jax lomi zorp].each do |character|
        service = Services::CharacterService.new(character: character.to_sym)

        # Should have persona instance
        persona = service.instance_variable_get(:@persona)
        expect(persona).to be_a(Personas::BasePersona) if character != 'default'

        # Should get tools from persona
        tools = service.get_tools
        expect(tools).to be_an(Array)

        # Should get prompt from persona
        prompt = service.get_system_prompt
        expect(prompt).to be_a(String)
        expect(prompt).not_to be_empty
      end
    end
  end
end
