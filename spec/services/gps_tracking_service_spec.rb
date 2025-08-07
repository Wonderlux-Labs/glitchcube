# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/gps_tracking_service'
require_relative '../../lib/home_assistant_client'

RSpec.describe Services::GpsTrackingService do
  let(:service) { described_class.new }
  let(:ha_client) { instance_double(HomeAssistantClient) }

  before do
    allow(HomeAssistantClient).to receive(:new).and_return(ha_client)
  end

  describe '#initialize' do
    it 'creates a HomeAssistantClient instance' do
      expect(HomeAssistantClient).to receive(:new)
      described_class.new
    end
  end

  describe '#current_location' do
    let(:device_tracker_entity) { 'device_tracker.glitch_cube' }

    before do
      allow(GlitchCube.config.gps).to receive(:device_tracker_entity).and_return(device_tracker_entity)
    end

    context 'when Home Assistant returns valid GPS data' do
      let(:ha_states) do
        [{
          'entity_id' => device_tracker_entity,
          'state' => 'home',
          'last_updated' => Time.now.iso8601,
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
      end

      it 'returns formatted GPS data' do
        result = service.current_location

        expect(result).to include(
          lat: 40.7863,
          lng: -119.2065,
          accuracy: 10,
          battery: 85
        )
        expect(result[:timestamp]).to be_a(Time)
        expect(result[:address]).to be_a(String)
        expect(result[:context]).to be_a(String)
      end
    end

    context 'when Home Assistant returns no GPS data' do
      before do
        allow(ha_client).to receive(:states).and_return([])
      end

      it 'returns random landmark location when no GPS data available' do
        result = service.current_location

        # Should return a random landmark location
        expect(result[:lat]).to be_a(Float)
        expect(result[:lng]).to be_a(Float)
        expect(result[:source]).to eq('random_location')
        expect(result[:accuracy]).to be_nil
        expect(result[:battery]).to be_nil
        expect(result[:timestamp]).to be_a(Time)
        
        # Should have computed BRC address and context
        expect(result[:address]).to be_a(String)
        expect(result[:brc_area]).to be_a(String)
        expect(result[:section]).to be_a(String)
        expect(result[:distance_from_man]).to match(/\d+\.\d+ mi from The Man/)
      end
    end

    context 'when Home Assistant raises an error' do
      before do
        allow(ha_client).to receive(:states).and_raise(StandardError.new('Connection failed'))
      end

      it 'returns random landmark location when error occurs' do
        result = service.current_location

        # Should fallback to random landmark location on error
        expect(result[:lat]).to be_a(Float)
        expect(result[:lng]).to be_a(Float)
        expect(result[:source]).to eq('random_location')
        expect(result[:accuracy]).to be_nil
        expect(result[:battery]).to be_nil
        expect(result[:timestamp]).to be_a(Time)
        
        # Should have computed BRC address and context
        expect(result[:address]).to be_a(String)
        expect(result[:brc_area]).to be_a(String)
        expect(result[:section]).to be_a(String)
        expect(result[:distance_from_man]).to match(/\d+\.\d+ mi from The Man/)
      end
    end
  end

  # NOTE: track_movement method doesn't exist in the service
  # These tests are commented out but kept for reference if the method is added later
  # describe '#track_movement' do
  #   # Test implementation would go here
  # end

  describe '#detect_nearby_landmarks' do
    context 'at Burning Man' do
      it 'detects when at Center Camp' do
        # Get Center Camp's actual coordinates from database
        center_camp_landmark = Landmark.find_by(name: 'Center Camp')
        skip 'Center Camp landmark not found in database' unless center_camp_landmark

        landmarks = service.detect_nearby_landmarks(center_camp_landmark.latitude, center_camp_landmark.longitude)

        center_camp = landmarks.find { |l| l[:name] == 'Center Camp' }
        expect(center_camp).not_to be_nil
        expect(center_camp[:distance]).to be < 0.01 # Should be very close
      end

      it 'detects multiple landmarks when in range' do
        # Find The Man coordinates and test nearby detection
        the_man_landmark = Landmark.find_by(name: 'The Man')
        skip 'The Man landmark not found in database' unless the_man_landmark

        landmarks = service.detect_nearby_landmarks(the_man_landmark.latitude, the_man_landmark.longitude)

        expect(landmarks).to be_an(Array)
        expect(landmarks).not_to be_empty
        # Should detect at least The Man
        expect(landmarks.map { |l| l[:name] }).to include('The Man')
      end

      it 'returns empty array when far from all landmarks' do
        # Far away location (San Francisco)
        landmarks = service.detect_nearby_landmarks(37.7749, -122.4194)

        expect(landmarks).to eq([])
      end
    end
  end

  # NOTE: journey_summary method doesn't exist in the service
  # These tests are commented out but kept for reference if the method is added later
  # describe '#journey_summary' do
  #   # Test implementation would go here
  # end

  describe 'LocationHelper integration' do
    it 'has access to haversine_distance method' do
      expect(service).to respond_to(:haversine_distance)
    end

    it 'calculates distance correctly' do
      # Test the haversine_distance method that was missing
      distance = service.haversine_distance(40.7864, -119.2065, 40.7900, -119.2100)

      expect(distance).to be_a(Float)
      expect(distance).to be > 0
      expect(distance).to be < 1 # Should be less than 1 mile for these coordinates
    end

    it 'has access to distance_from method' do
      expect(service).to respond_to(:distance_from)
    end

    it 'has access to coordinates method' do
      expect(service).to respond_to(:coordinates)
    end
  end

  describe 'error handling' do
    it 'handles missing configuration gracefully' do
      allow(GlitchCube.config).to receive(:gps).and_raise(NoMethodError)
      allow(ha_client).to receive(:states).and_return([])

      # Should fall back to ENV variable
      expect { service.current_location }.not_to raise_error
    end
  end
end
