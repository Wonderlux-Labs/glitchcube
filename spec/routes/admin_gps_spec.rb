# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Admin GPS Spoofing' do
  let(:redis) { instance_double(Redis) }

  before do
    # Mock Redis connection
    allow(Redis).to receive(:new).and_return(redis)
    allow(redis).to receive(:set)
    allow(redis).to receive(:del)
    allow(redis).to receive(:get)

    # Mock services
    allow(Services::LoggerService).to receive(:log_api_call)

    # Mock environment to be development for all tests except the restriction tests
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('RACK_ENV').and_return('development')
  end

  describe 'GPS Spoofing endpoints' do
    describe 'Environment restrictions' do
      context 'when in production environment' do
        before do
          # Override the default development mock to simulate production
          allow(ENV).to receive(:[]).with('RACK_ENV').and_return('production')
        end

        it 'blocks landmarks endpoint' do
          get '/admin/landmarks'

          expect(last_response.status).to eq(403)
          parsed = JSON.parse(last_response.body)

          expect(parsed['success']).to be false
          expect(parsed['error']).to include('only available in development environment')
        end

        it 'blocks GPS spoofing endpoint' do
          post '/admin/spoof_gps', { latitude: 40.7864, longitude: -119.2034 }.to_json, 'CONTENT_TYPE' => 'application/json'

          expect(last_response.status).to eq(403)
          parsed = JSON.parse(last_response.body)

          expect(parsed['success']).to be false
          expect(parsed['error']).to include('only available in development environment')
        end

        it 'blocks clear spoofing endpoint' do
          delete '/admin/spoof_gps'

          expect(last_response.status).to eq(403)
          parsed = JSON.parse(last_response.body)

          expect(parsed['success']).to be false
          expect(parsed['error']).to include('only available in development environment')
        end

        it 'allows current location endpoint (not blocked in production)' do
          # Mock GPS service for this test
          gps_service = instance_double(Services::GpsTrackingService)
          allow(Services::GpsTrackingService).to receive(:new).and_return(gps_service)
          allow(gps_service).to receive(:current_location).and_return({
                                                                        lat: 40.786400,
                                                                        lng: -119.203400,
                                                                        source: 'test'
                                                                      })

          get '/admin/current_location'

          expect(last_response.status).to eq(200)
          parsed = JSON.parse(last_response.body)

          expect(parsed['success']).to be true
          expect(parsed).to have_key('location')
        end
      end
    end

    describe 'GET /admin/landmarks' do
      it 'returns active landmarks' do
        get '/admin/landmarks'

        expect(last_response.status).to eq(200)
        parsed = JSON.parse(last_response.body)

        expect(parsed['success']).to be true
        expect(parsed['landmarks']).to be_an(Array)
        expect(parsed['landmarks'].size).to be > 0
      end

      it 'includes required landmark data' do
        get '/admin/landmarks'

        parsed = JSON.parse(last_response.body)
        return if parsed['landmarks'].empty?

        landmark = parsed['landmarks'].first

        expect(landmark).to have_key('id')
        expect(landmark).to have_key('name')
        expect(landmark).to have_key('latitude')
        expect(landmark).to have_key('longitude')
        expect(landmark).to have_key('landmark_type')
        expect(landmark).to have_key('description')
      end
    end

    describe 'POST /admin/spoof_gps' do
      let(:spoof_data) do
        {
          latitude: 40.786400,
          longitude: -119.203400,
          name: 'Test Location'
        }
      end

      it 'successfully spoofs GPS location' do
        expect(redis).to receive(:set).with('current_cube_location', anything)
        expect(redis).to receive(:set).with('cube_simulate_movement', 'true')

        post '/admin/spoof_gps', spoof_data.to_json, 'CONTENT_TYPE' => 'application/json'

        expect(last_response.status).to eq(200)
        parsed = JSON.parse(last_response.body)

        expect(parsed['success']).to be true
        expect(parsed['message']).to include('GPS spoofed to Test Location')
        expect(parsed['location']['lat']).to eq(40.786400)
        expect(parsed['location']['lng']).to eq(-119.203400)
      end

      it 'logs the GPS spoofing action' do
        expect(Services::LoggerService).to receive(:log_api_call).with(
          hash_including(
            service: 'admin',
            endpoint: 'spoof_gps',
            method: 'POST',
            latitude: 40.786400,
            longitude: -119.203400,
            name: 'Test Location',
            success: true
          )
        )

        post '/admin/spoof_gps', spoof_data.to_json, 'CONTENT_TYPE' => 'application/json'
      end

      it 'requires latitude and longitude' do
        post '/admin/spoof_gps', { name: 'Test' }.to_json, 'CONTENT_TYPE' => 'application/json'

        expect(last_response.status).to eq(400)
        parsed = JSON.parse(last_response.body)

        expect(parsed['success']).to be false
        expect(parsed['error']).to include('Latitude and longitude are required')
      end

      it 'handles Redis errors gracefully' do
        allow(redis).to receive(:set).and_raise(Redis::CannotConnectError.new('Connection failed'))

        post '/admin/spoof_gps', spoof_data.to_json, 'CONTENT_TYPE' => 'application/json'

        expect(last_response.status).to eq(500)
        parsed = JSON.parse(last_response.body)

        expect(parsed['success']).to be false
        expect(parsed['error']).to include('Connection failed')
      end
    end

    describe 'DELETE /admin/spoof_gps' do
      it 'successfully clears GPS spoofing' do
        expect(redis).to receive(:del).with('current_cube_location')
        expect(redis).to receive(:set).with('cube_simulate_movement', 'false')

        delete '/admin/spoof_gps'

        expect(last_response.status).to eq(200)
        parsed = JSON.parse(last_response.body)

        expect(parsed['success']).to be true
        expect(parsed['message']).to include('GPS spoofing cleared')
      end

      it 'logs the clear action' do
        expect(Services::LoggerService).to receive(:log_api_call).with(
          hash_including(
            service: 'admin',
            endpoint: 'clear_gps_spoof',
            method: 'DELETE',
            success: true
          )
        )

        delete '/admin/spoof_gps'
      end

      it 'handles Redis errors gracefully' do
        allow(redis).to receive(:del).and_raise(Redis::CannotConnectError.new('Connection failed'))

        delete '/admin/spoof_gps'

        expect(last_response.status).to eq(500)
        parsed = JSON.parse(last_response.body)

        expect(parsed['success']).to be false
        expect(parsed['error']).to include('Connection failed')
      end
    end

    describe 'GET /admin/current_location' do
      let(:gps_service) { instance_double(Services::GpsTrackingService) }
      let(:current_location) do
        {
          lat: 40.786400,
          lng: -119.203400,
          timestamp: Time.now,
          source: 'admin_spoof',
          name: 'Test Location'
        }
      end

      before do
        allow(Services::GpsTrackingService).to receive(:new).and_return(gps_service)
      end

      it 'returns current GPS location' do
        expect(gps_service).to receive(:current_location).and_return(current_location)

        get '/admin/current_location'

        expect(last_response.status).to eq(200)
        parsed = JSON.parse(last_response.body)

        expect(parsed['success']).to be true
        expect(parsed['location']['lat']).to eq(40.786400)
        expect(parsed['location']['lng']).to eq(-119.203400)
        expect(parsed['location']['source']).to eq('admin_spoof')
      end

      it 'handles GPS service errors gracefully' do
        expect(gps_service).to receive(:current_location).and_raise(StandardError.new('GPS unavailable'))

        get '/admin/current_location'

        expect(last_response.status).to eq(500)
        parsed = JSON.parse(last_response.body)

        expect(parsed['success']).to be false
        expect(parsed['error']).to include('GPS unavailable')
      end
    end
  end

  describe 'GPS spoofing integration with GpsTrackingService' do
    let(:gps_service) { Services::GpsTrackingService.new }

    before do
      # Mock simulation mode check
      allow(Cube::Settings).to receive(:simulate_cube_movement?).and_return(true)
    end

    it 'GPS service uses spoofed coordinates from Redis' do
      spoofed_location = {
        lat: 40.786400,
        lng: -119.203400,
        timestamp: Time.now.iso8601,
        source: 'admin_spoof',
        name: 'Test Location'
      }

      allow(redis).to receive(:get).with('current_cube_location').and_return(spoofed_location.to_json)
      allow(Redis).to receive(:new).and_return(redis)

      location = gps_service.current_location

      expect(location[:lat]).to eq(40.786400)
      expect(location[:lng]).to eq(-119.203400)
      expect(location[:source]).to eq('simulation')
    end
  end
end
