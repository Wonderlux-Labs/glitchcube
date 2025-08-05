# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'

RSpec.describe GlitchCube::Routes::Core::Kiosk do
  include Rack::Test::Methods

  def app
    GlitchCubeApp
  end

  describe 'GET /kiosk' do
    it 'returns the kiosk view' do
      get '/kiosk'
      expect(last_response).to be_ok
      expect(last_response.body).to include('<!DOCTYPE html>')
    end
  end

  describe 'GET /api/v1/kiosk/status' do
    context 'when kiosk service is available' do
      let(:mock_status) do
        {
          battery_level: 85,
          location: 'Black Rock City',
          last_interaction: Time.now.iso8601,
          active_personality: 'glitch',
          mood: 'curious'
        }
      end

      before do
        allow_any_instance_of(Services::KioskService).to receive(:get_status).and_return(mock_status)
      end

      it 'returns kiosk status as JSON' do
        get '/api/v1/kiosk/status'
        expect(last_response).to be_ok
        expect(last_response.content_type).to include('application/json')
        
        body = JSON.parse(last_response.body)
        expect(body['battery_level']).to eq(85)
        expect(body['location']).to eq('Black Rock City')
        expect(body['active_personality']).to eq('glitch')
      end
    end

    context 'when kiosk service fails' do
      before do
        allow_any_instance_of(Services::KioskService).to receive(:get_status).and_raise(StandardError, 'Service unavailable')
      end

      it 'returns error response' do
        get '/api/v1/kiosk/status'
        expect(last_response.status).to eq(500)
        expect(last_response.content_type).to include('application/json')
        
        body = JSON.parse(last_response.body)
        expect(body['error']).to eq('Service unavailable')
        expect(body['timestamp']).to be_present
      end
    end
  end
end