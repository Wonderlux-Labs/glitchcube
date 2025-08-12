# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Services::LocationContextService do
  let(:lat) { 40.7863 }
  let(:lng) { -119.2065 }
  let(:service) { described_class.new(lat, lng) }

  # Mock Redis to avoid external dependencies
  let(:redis) { instance_double(Redis) }

  before do
    allow(Redis).to receive(:new).and_return(redis)
    allow(redis).to receive(:get).and_return(nil)
    allow(redis).to receive(:setex)

    # Mock database calls to avoid complex setup
    allow(Boundary).to receive(:cube_within_fence?).and_return(true)
    allow(Boundary).to receive(:in_city?).and_return(true)
    allow(Street).to receive(:nearest_intersection).and_return({ radial: '6:00', arc: 'Esplanade' })
    allow(Landmark).to receive(:nearest).and_return([])
    allow(Landmark).to receive(:the_man).and_return(double(distance_from: 500))
  end

  describe '#initialize' do
    it 'sets latitude and longitude as floats' do
      expect(service.lat).to eq(40.7863)
      expect(service.lng).to eq(-119.2065)
      expect(service.lat_lng).to eq({ lat: 40.7863, lng: -119.2065 })
    end
  end

  describe '.full_context' do
    it 'creates instance and calls full_context' do
      service_instance = instance_double(described_class)
      allow(described_class).to receive(:new).with(lat, lng).and_return(service_instance)
      allow(service_instance).to receive(:full_context).and_return({ zone: :city })

      result = described_class.full_context(lat, lng)
      expect(result).to eq({ zone: :city })
    end
  end

  describe '#full_context' do
    let(:expected_result) do
      {
        zone: :city,
        address: '6:00 & Esplanade',
        intersection: { radial: '6:00', arc: 'Esplanade' },
        landmarks: [],
        within_fence: true,
        city_block: nil,
        distance_from_man: '1640 feet',
        nearest_porto: [],
        lat_lng: { lat: lat, lng: lng }
      }
    end

    context 'when not in cache' do
      it 'computes full context and caches result' do
        allow(service).to receive(:zone).and_return(:city)
        allow(service).to receive(:address).and_return('6:00 & Esplanade')
        allow(service).to receive(:nearest_intersection).and_return({ radial: '6:00', arc: 'Esplanade' })
        allow(service).to receive(:nearby_landmarks).and_return([])
        allow(service).to receive(:within_fence?).and_return(true)
        allow(service).to receive(:city_block).and_return(nil)
        allow(service).to receive(:distance_from_man).and_return('1640 feet')
        allow(service).to receive(:nearest_porto).and_return([])

        result = service.full_context

        expect(result).to include(
          zone: :city,
          address: '6:00 & Esplanade',
          within_fence: true
        )

        # Should cache the result
        expect(redis).to have_received(:setex).with(
          "location_context:#{lat.round(6)},#{lng.round(6)}",
          300,
          anything
        )
      end
    end

    context 'when in cache' do
      let(:cached_result) { { zone: 'city', cached: true }.to_json }

      before do
        allow(redis).to receive(:get).and_return(cached_result)
      end

      it 'returns cached result' do
        result = service.full_context

        expect(result).to eq({ zone: 'city', cached: true })
        expect(redis).not_to have_received(:setex)
      end
    end

    context 'when Redis fails' do
      before do
        allow(redis).to receive(:get).and_raise(Redis::CannotConnectError)
        allow(redis).to receive(:setex).and_raise(Redis::CannotConnectError)
      end

      it 'computes result without caching' do
        allow(service).to receive(:zone).and_return(:city)
        allow(service).to receive(:address).and_return('6:00 & Esplanade')

        result = service.full_context

        expect(result[:zone]).to eq(:city)
        # Should not raise error despite Redis failures
      end
    end
  end

  describe '#zone' do
    context 'outside event' do
      before { allow(service).to receive(:within_fence?).and_return(false) }

      it 'returns :outside_event' do
        expect(service.zone).to eq(:outside_event)
      end
    end

    context 'in city' do
      before do
        allow(service).to receive(:within_fence?).and_return(true)
        allow(service).to receive(:in_city?).and_return(true)
      end

      it 'returns :city' do
        expect(service.zone).to eq(:city)
      end
    end

    context 'near The Man' do
      before do
        allow(service).to receive(:within_fence?).and_return(true)
        allow(service).to receive(:in_city?).and_return(false)
        allow(service).to receive(:near_the_man?).and_return(true)
      end

      it 'returns :inner_playa' do
        expect(service.zone).to eq(:inner_playa)
      end
    end

    context 'deep playa' do
      before do
        allow(service).to receive(:within_fence?).and_return(true)
        allow(service).to receive(:in_city?).and_return(false)
        allow(service).to receive(:near_the_man?).and_return(false)
      end

      it 'returns :deep_playa' do
        expect(service.zone).to eq(:deep_playa)
      end
    end
  end

  describe '#address' do
    context 'in city' do
      before do
        allow(service).to receive(:zone).and_return(:city)
        allow(service).to receive(:nearest_intersection).and_return({ radial: '6:00', arc: 'Esplanade' })
      end

      it 'returns intersection address' do
        expect(service.address).to eq('6:00 & Esplanade')
      end
    end

    context 'not in city' do
      before { allow(service).to receive(:zone).and_return(:deep_playa) }

      it 'returns nil' do
        expect(service.address).to be_nil
      end
    end
  end

  describe '#near_the_man?' do
    let(:the_man) { double(id: 1) }
    let(:nearby_landmarks) { [double(id: 1)] }

    before do
      allow(Landmark).to receive(:find_by).with(name: 'The Man').and_return(the_man)
    end

    context 'when within radius of The Man' do
      before do
        allow(Landmark).to receive(:nearest).with(
          lat: lat, lng: lng, limit: 1, max_distance_meters: 757
        ).and_return(nearby_landmarks)
      end

      it 'returns true' do
        expect(service.near_the_man?).to be true
      end
    end

    context 'when not within radius' do
      before do
        allow(Landmark).to receive(:nearest).and_return([])
      end

      it 'returns false' do
        expect(service.near_the_man?).to be false
      end
    end
  end

  describe '#nearby_landmarks' do
    let(:landmark) { double(name: 'Test', landmark_type: 'art', distance_meters: 100) }

    before do
      allow(Landmark).to receive(:nearest).with(lat: lat, lng: lng, limit: 3).and_return([landmark])
    end

    it 'returns formatted landmark data' do
      result = service.nearby_landmarks(3)

      expect(result).to eq([{
                             name: 'Test',
                             type: 'art',
                             distance_meters: 100
                           }])
    end
  end

  describe '#distance_from_man' do
    let(:the_man) { double(distance_from: 500.0) }

    before do
      allow(Landmark).to receive(:the_man).and_return(the_man)
    end

    it 'returns formatted distance' do
      result = service.distance_from_man

      expect(result).to eq('0.31 miles') # 500m ≈ 0.31 miles
    end

    context 'when The Man not found' do
      before { allow(Landmark).to receive(:the_man).and_return(nil) }

      it 'returns Unknown' do
        expect(service.distance_from_man).to eq('Unknown')
      end
    end
  end

  describe '#format_distance (private)' do
    it 'formats short distances in feet' do
      # Test via distance_from_man which calls format_distance
      the_man = double(distance_from: 100.0) # 100 meters
      allow(Landmark).to receive(:the_man).and_return(the_man)

      result = service.distance_from_man
      expect(result).to eq('328 feet') # 100m ≈ 328 feet
    end

    it 'formats long distances in miles' do
      the_man = double(distance_from: 2000.0) # 2000 meters
      allow(Landmark).to receive(:the_man).and_return(the_man)

      result = service.distance_from_man
      expect(result).to eq('1.24 miles') # 2000m ≈ 1.24 miles
    end
  end
end
