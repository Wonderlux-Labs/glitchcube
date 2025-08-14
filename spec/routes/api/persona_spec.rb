# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'

RSpec.describe 'Persona API Endpoints' do
  include Rack::Test::Methods

  def app
    GlitchCubeApp
  end

  before do
    # Register personas
    Personas::PersonaFactory.register_all

    # Clear any existing state
    Services::PersonaStateService.clear_state!
  end

  after do
    # Clear state after each test to prevent pollution
    Services::PersonaStateService.clear_state!
  end

  describe 'GET /api/v1/persona' do
    it 'returns the current persona' do
      get '/api/v1/persona'

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)

      expect(json['success']).to be true
      expect(json['current_persona']).to eq('buddy') # Default
      expect(json).to have_key('usage_stats')
    end

    it 'returns persona set via service' do
      Services::PersonaStateService.set_current_persona('jax', sync_with_ha: false)

      get '/api/v1/persona'

      json = JSON.parse(last_response.body)
      expect(json['current_persona']).to eq('jax')
    end
  end

  describe 'POST /api/v1/persona' do
    it 'changes the current persona' do
      post '/api/v1/persona', { persona: 'zorp' }.to_json, 'CONTENT_TYPE' => 'application/json'

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)

      expect(json['success']).to be true
      expect(json['persona']).to eq('zorp')
      expect(json['message']).to include('zorp')
    end

    it 'returns error for missing persona parameter' do
      post '/api/v1/persona', {}.to_json, 'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(400)
      json = JSON.parse(last_response.body)

      expect(json['success']).to be false
      expect(json['error']).to include('Missing persona')
    end

    it 'returns error for unknown persona' do
      post '/api/v1/persona', { persona: 'unknown' }.to_json, 'CONTENT_TYPE' => 'application/json'

      expect(last_response.status).to eq(400)
      json = JSON.parse(last_response.body)

      expect(json['success']).to be false
      expect(json['error']).to include('Unknown persona')
    end
  end

  describe 'GET /api/v1/personas' do
    xit 'lists all available personas' do
      # TODO: Persona API test - may need adjustment for response format or persona registration
      get '/api/v1/personas'

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)

      expect(json['success']).to be true
      expect(json['personas']).to be_an(Array)
      expect(json['personas'].size).to eq(4) # buddy, jax, lomi, zorp

      buddy = json['personas'].find { |p| p['name'] == 'buddy' }
      expect(buddy).to be_present
      expect(buddy['active']).to be true # Default persona
      expect(buddy['display_name']).to eq('Buddy')
    end

    it 'correctly marks active persona' do
      Services::PersonaStateService.set_current_persona('lomi', sync_with_ha: false)

      get '/api/v1/personas'

      json = JSON.parse(last_response.body)
      lomi = json['personas'].find { |p| p['name'] == 'lomi' }
      buddy = json['personas'].find { |p| p['name'] == 'buddy' }

      expect(lomi['active']).to be true
      expect(buddy['active']).to be false
    end
  end

  describe 'POST /api/v1/persona/sync' do
    let(:ha_client) { instance_double(Core::HomeAssistantClient) }

    before do
      allow(Core::HomeAssistantClient).to receive(:new).and_return(ha_client)
    end

    it 'syncs from Home Assistant by default' do
      allow(ha_client).to receive(:state).with('input_text.current_persona')
                                         .and_return({ 'state' => 'Jax' })

      post '/api/v1/persona/sync'

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)

      expect(json['success']).to be true
      expect(json['message']).to include('Synced from Home Assistant')
      expect(json['current_persona']).to eq('jax')
    end

    it 'syncs to Home Assistant when requested' do
      expect(ha_client).to receive(:set_state)

      post '/api/v1/persona/sync', { direction: 'to_ha' }.to_json, 'CONTENT_TYPE' => 'application/json'

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)

      expect(json['success']).to be true
      expect(json['message']).to include('Synced to Home Assistant')
    end
  end

  describe 'DELETE /api/v1/persona/state' do
    it 'clears all persona state' do
      Services::PersonaStateService.set_current_persona('zorp', sync_with_ha: false)

      delete '/api/v1/persona/state'

      expect(last_response).to be_ok
      json = JSON.parse(last_response.body)

      expect(json['success']).to be true
      expect(json['message']).to include('cleared')

      # Verify state was cleared
      expect(Services::PersonaStateService.get_current_persona).to eq('buddy')
    end
  end
end
