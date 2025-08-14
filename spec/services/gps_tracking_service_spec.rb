# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/gps/gps_tracking_service'
require_relative '../../lib/services/gps/location_context_service'

RSpec.describe Services::Gps::GPSTrackingService do
  let(:service) { described_class.new }
  let(:ha_client) { instance_double(HomeAssistantClient) }

  before do
    allow(HomeAssistantClient).to receive(:new).and_return(ha_client)

    # Mock LocationContextService to avoid complex setup
    allow(Services::Gps::LocationContextService).to receive(:full_context).and_return({
                                                                                        zone: :city,
                                                                                        address: '6:00 & Esplanade',
                                                                                        within_fence: true,
                                                                                        distance_from_man: '0.5 miles',
                                                                                        landmarks: []
                                                                                      })
  end

  describe '#current_location' do
    context 'with Home Assistant GPS data' do
      let(:ha_states) do
        [{
          'entity_id' => 'device_tracker.glitch_cube',
          'state' => 'home',
          'last_updated' => '2025-01-01T12:00:00Z',
          'attributes' => {
            'latitude' => 40.7863,
            'longitude' => -119.2065,
            'gps_accuracy' => 10,
            'battery_level' => 85
          }
        }]
      end

      before do
        allow(ha_client).to receive(:states).and_return(ha_states)
        allow(GlitchCube.config.gps).to receive(:device_tracker_entity).and_return('device_tracker.glitch_cube')
      end

      it 'returns GPS data merged with location context' do
        result = service.current_location

        # GPS metadata
        expect(result).to include(
          lat: 40.7863,
          lng: -119.2065,
          source: 'gps',
          accuracy: 10,
          battery: 85
        )
        expect(result[:timestamp]).to be_a(Time)

        # Location context
        expect(result).to include(
          zone: :city,
          address: '6:00 & Esplanade',
          within_fence: true,
          distance_from_man: '0.5 miles'
        )
      end
    end

    context 'with no GPS data available' do
      before do
        allow(ha_client).to receive(:states).and_return([])
      end

      it 'falls back to random landmark location' do
        result = service.current_location

        expect(result[:lat]).to be_a(Float)
        expect(result[:lng]).to be_a(Float)
        expect(result[:source]).to eq('random_landmark')
        expect(result[:accuracy]).to be_nil
        expect(result[:battery]).to be_nil

        # Should still have location context
        expect(result[:zone]).to eq(:city)
        expect(result[:address]).to eq('6:00 & Esplanade')
      end
    end

    context 'with spoofed GPS (development mode)' do
      let(:redis) { instance_double(Redis) }
      let(:spoofed_location) do
        {
          lat: 40.7800,
          lng: -119.2100,
          timestamp: Time.now.iso8601,
          source: 'spoofed',
          name: 'Test Location'
        }
      end

      before do
        allow(Redis).to receive(:new).and_return(redis)
        allow(redis).to receive(:get).with('current_cube_location').and_return(spoofed_location.to_json)
        allow(ENV).to receive(:[]).with('RACK_ENV').and_return('development')
        allow(ENV).to receive(:[]).with('REDIS_URL').and_return('redis://localhost:6379/0')
      end

      it 'uses spoofed location when available in development' do
        result = service.current_location

        expect(result[:lat]).to eq(40.7800)
        expect(result[:lng]).to eq(-119.2100)
        expect(result[:source]).to eq('spoofed')
        # Name field is not preserved from spoofed location

        # Should still get location context
        expect(result[:zone]).to eq(:city)
      end
    end
  end

  describe '#proximity_data' do
    let(:context_with_landmarks) do
      {
        landmarks: [
          { name: 'The Man', type: 'center', distance_meters: 100 },
          { name: 'Temple', type: 'sacred', distance_meters: 200 }
        ],
        nearest_porto: { name: 'Porto 1', type: 'toilet', distance_meters: 50 }
      }
    end

    before do
      allow(Services::Gps::LocationContextService).to receive(:full_context)
        .with(40.7863, -119.2065)
        .and_return(context_with_landmarks)
    end

    it 'returns formatted proximity data with map mode and visual effects' do
      result = service.proximity_data(40.7863, -119.2065)

      expect(result).to include(
        landmarks: context_with_landmarks[:landmarks],
        portos: [context_with_landmarks[:nearest_porto]],
        map_mode: 'man' # 'center' type maps to 'man' mode
      )

      # Visual effects should include both center (pulse) and sacred (aura) effects
      expect(result[:visual_effects]).to include(
        { type: 'pulse', color: 'orange', intensity: 'strong' },
        { type: 'aura', color: 'white', intensity: 'soft' }
      )
    end

    it 'handles empty landmarks gracefully' do
      allow(Services::Gps::LocationContextService).to receive(:full_context).and_return({ landmarks: [] })

      result = service.proximity_data(40.7863, -119.2065)

      expect(result[:map_mode]).to eq('normal')
      expect(result[:visual_effects]).to eq([])
    end
  end

  describe '#brc_address_from_coordinates (deprecated)' do
    it 'delegates to LocationContextService' do
      expect(Services::Gps::LocationContextService).to receive(:full_context)
        .with(40.7863, -119.2065)
        .and_return({ address: '6:00 & Esplanade' })

      result = service.brc_address_from_coordinates(40.7863, -119.2065)
      expect(result).to eq('6:00 & Esplanade')
    end
  end

  describe 'private methods' do
    describe '#determine_map_mode_from_landmarks' do
      it 'maps landmark types to visual modes' do
        landmarks = [{ type: 'sacred' }]
        result = service.send(:determine_map_mode_from_landmarks, landmarks)
        expect(result).to eq('temple')

        landmarks = [{ type: 'center' }]
        result = service.send(:determine_map_mode_from_landmarks, landmarks)
        expect(result).to eq('man')

        landmarks = [{ type: 'medical' }]
        result = service.send(:determine_map_mode_from_landmarks, landmarks)
        expect(result).to eq('emergency')
      end
    end

    describe '#determine_visual_effects_from_landmarks' do
      it 'creates visual effects based on landmark types' do
        landmarks = [
          { type: 'sacred' },
          { type: 'center' },
          { type: 'medical' }
        ]

        result = service.send(:determine_visual_effects_from_landmarks, landmarks)

        expect(result).to include(
          { type: 'aura', color: 'white', intensity: 'soft' },
          { type: 'pulse', color: 'orange', intensity: 'strong' },
          { type: 'beacon', color: 'red', intensity: 'steady' }
        )
      end
    end
  end
end
