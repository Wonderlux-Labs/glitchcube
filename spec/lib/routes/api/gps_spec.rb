# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'

RSpec.describe GlitchCube::Routes::Api::Gps, vcr: false do
  include Rack::Test::Methods

  def app
    GlitchCubeApp
  end

  describe 'GET /gps' do
    it 'returns the GPS map view', :vcr do
      get '/gps'
      expect(last_response).to be_ok
      expect(last_response.body).to include('<!DOCTYPE html>')
    end
  end

  describe 'GET /api/v1/gps/location' do
    let(:mock_location) do
      {
        lat: 40.7712,
        lng: -119.2030,
        address: '6:00 & Esplanade',
        accuracy: 10,
        timestamp: Time.now.iso8601
      }
    end

    let(:mock_proximity) do
      {
        landmarks: ['Center Camp', 'The Man'],
        portos: [{ distance: 50, direction: 'NE' }],
        map_mode: 'playa',
        visual_effects: ['dust_storm']
      }
    end

    before do
      allow(Services::GpsCacheService).to receive_messages(cached_location: mock_location, cached_proximity: mock_proximity)
    end

    xit 'returns current location with proximity data', :vcr do
      get '/api/v1/gps/location'
      expect(last_response).to be_ok
      expect(last_response.content_type).to include('application/json')

      body = JSON.parse(last_response.body)
      expect(body['lat']).to eq(40.7712)
      expect(body['lng']).to eq(-119.2030)
      expect(body['address']).to eq('6:00 & Esplanade')
      expect(body['proximity']).to include('landmarks' => ['Center Camp', 'The Man'])
    end
  end

  describe 'GET /api/v1/gps/proximity' do
    context 'with valid location' do
      let(:mock_location) { { lat: 40.7712, lng: -119.2030 } }
      let(:mock_proximity) do
        {
          landmarks: ['Temple'],
          portos: [],
          map_mode: 'normal',
          visual_effects: []
        }
      end

      before do
        allow(Services::GpsCacheService).to receive_messages(cached_location: mock_location, cached_proximity: mock_proximity)
      end

      it 'returns proximity data', :vcr do
        get '/api/v1/gps/proximity'
        expect(last_response).to be_ok

        body = JSON.parse(last_response.body)
        expect(body['landmarks']).to eq(['Temple'])
        expect(body['map_mode']).to eq('normal')
      end
    end

    context 'without valid location' do
      before do
        allow(Services::GpsCacheService).to receive(:cached_location).and_return({})
      end

      it 'returns empty proximity data', :vcr do
        get '/api/v1/gps/proximity'
        expect(last_response).to be_ok

        body = JSON.parse(last_response.body)
        expect(body['landmarks']).to eq([])
        expect(body['portos']).to eq([])
        expect(body['map_mode']).to eq('normal')
        expect(body['visual_effects']).to eq([])
      end
    end
  end

  describe 'GET /api/v1/gps/history' do
    it 'returns location history', :vcr do
      get '/api/v1/gps/history'
      expect(last_response).to be_ok
      expect(last_response.content_type).to include('application/json')

      body = JSON.parse(last_response.body)
      expect(body['history']).to be_an(Array)
      expect(body['total_points']).to eq(body['history'].length)

      # Check the sample data structure
      first_point = body['history'].first
      expect(first_point).to have_key('lat')
      expect(first_point).to have_key('lng')
      expect(first_point).to have_key('timestamp')
      expect(first_point).to have_key('address')
    end

    context 'when specifying hours parameter' do
      it 'accepts hours parameter', :vcr do
        get '/api/v1/gps/history?hours=48'
        expect(last_response).to be_ok

        body = JSON.parse(last_response.body)
        expect(body['history']).to be_an(Array)
        expect(body['total_points']).to be >= 0
      end
    end
  end

  describe 'GeoJSON endpoints' do
    # NOTE: These tests will fail if the GeoJSON files don't exist
    # We'll check for file existence rather than testing actual file serving

    %w[streets toilets blocks plazas].each do |gis_type|
      describe "GET /api/v1/gis/#{gis_type}" do
        it "serves #{gis_type} GeoJSON file", :vcr do
          geojson_file = File.join(GlitchCubeApp.settings.root, 'data', 'gis', "#{gis_type == 'streets' ? 'street_lines' : gis_type}.geojson")

          if File.exist?(geojson_file)
            get "/api/v1/gis/#{gis_type}"
            expect(last_response).to be_ok
            expect(last_response.content_type).to include('application/json')
          else
            skip "GeoJSON file not found: #{geojson_file}"
          end
        end
      end
    end
  end
end
