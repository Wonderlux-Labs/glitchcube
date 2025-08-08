# frozen_string_literal: true

RSpec.describe TestTool do
  describe '.name' do
    it 'returns the tool name' do
      expect(described_class.name).to eq('test_tool')
    end
  end

  describe '.description' do
    it 'returns the tool description' do
      expect(described_class.description).to eq('Get system information. Args: info_type (string) - battery, location, sensors, or all')
    end
  end

  describe '.call' do
    context 'when requesting battery info' do
      it 'returns battery status' do
        result = described_class.call(info_type: 'battery')
        expect(result).to include('battery_level: 87%')
        expect(result).to include('charging: false')
        expect(result).to include('time_remaining: 21 hours')
        expect(result).to include('solar_panel_status: inactive (nighttime)')
      end
    end

    context 'when requesting location info' do
      it 'returns location data' do
        result = described_class.call(info_type: 'location')
        expect(result).to include('current_location: Art Gallery Main Hall')
        expect(result).to include('gps_coordinates: 40.7128° N, 74.0060° W')
        expect(result).to include('elevation: 10 meters')
        expect(result).to include('last_moved: 2 hours ago')
      end
    end

    context 'when requesting sensor info' do
      it 'returns sensor readings' do
        result = described_class.call(info_type: 'sensors')
        expect(result).to include('temperature: 22°C')
        expect(result).to include('humidity: 45%')
        expect(result).to include('light_level: moderate')
        expect(result).to include('motion_detected: true')
        expect(result).to include('sound_level: 65 dB')
        expect(result).to include('proximity_sensors:')
        expect(result).to include('2.3 meters')
      end
    end

    context 'when requesting all info' do
      it 'returns all system information' do
        result = described_class.call(info_type: 'all')
        expect(result).to include('battery:')
        expect(result).to include('location:')
        expect(result).to include('sensors:')
        expect(result).to include('battery_level: 87%')
        expect(result).to include('Art Gallery Main Hall')
        expect(result).to include('temperature: 22°C')
      end
    end

    context 'with invalid info type' do
      it 'returns an error' do
        result = described_class.call(info_type: 'invalid')
        expect(result).to eq('❌ Unknown info type: invalid')
      end
    end
  end
end
