require 'spec_helper'

RSpec.describe WeatherService, :vcr do
  let(:service) { described_class.new }
  let(:mock_ha_states) do
    [
      {
        'entity_id' => 'weather.home',
        'state' => 'sunny',
        'attributes' => {
          'temperature' => 85.5,
          'humidity' => 45,
          'pressure' => 30.2,
          'wind_speed' => 8.5,
          'wind_bearing' => 180,
          'forecast' => [
            {
              'datetime' => '2024-08-04T18:00:00+00:00',
              'condition' => 'clear',
              'temperature' => 68
            },
            {
              'datetime' => '2024-08-05T06:00:00+00:00', 
              'condition' => 'partly-cloudy',
              'temperature' => 72
            }
          ]
        }
      },
      {
        'entity_id' => 'sensor.outdoor_temperature',
        'state' => '84.2',
        'attributes' => { 'unit_of_measurement' => '°F' }
      },
      {
        'entity_id' => 'sensor.outdoor_humidity',
        'state' => '42',
        'attributes' => { 'unit_of_measurement' => '%' }
      }
    ]
  end

  describe '#update_weather_summary' do
    context 'when Home Assistant is available' do
      before do
        allow(GlitchCube.config).to receive(:mock_home_assistant?).and_return(false)
        allow(GlitchCube.config).to receive(:installation_location).and_return('Black Rock Desert')
      end

      it 'fetches weather data and generates summary', :vcr do
        # Mock the Home Assistant API response
        stub_request(:get, "#{GlitchCube.config.home_assistant.url}/api/states")
          .with(headers: {
            'Authorization' => "Bearer #{GlitchCube.config.home_assistant.token}",
            'Content-Type' => 'application/json'
          })
          .to_return(
            status: 200,
            body: mock_ha_states.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        # Mock the webhook update to HA
        webhook_stub = stub_request(:post, "#{GlitchCube.config.home_assistant.url}/api/webhook/glitchcube_weather")
          .with(
            body: hash_including('weather'),
            headers: { 'Content-Type' => 'application/json' }
          )
          .to_return(status: 200, body: '{"status": "ok"}')

        result = service.update_weather_summary

        expect(result).to be_a(String)
        expect(result.length).to be <= 255
        expect(result).not_to eq('Weather data unavailable')
        expect(result).not_to include('Weather error')
        
        # Verify it contains weather-related information
        expect(result.downcase).to match(/temperature|sunny|clear|wind|humid/i)
        
        # Verify webhook was called
        expect(webhook_stub).to have_been_requested
      end

      it 'handles missing weather data gracefully' do
        # Mock empty response from HA
        stub_request(:get, "#{GlitchCube.config.home_assistant.url}/api/states")
          .to_return(status: 200, body: '[]', headers: { 'Content-Type' => 'application/json' })

        result = service.update_weather_summary
        expect(result).to eq('No weather data')
      end

      it 'handles API errors gracefully' do
        # Mock network error
        stub_request(:get, "#{GlitchCube.config.home_assistant.url}/api/states")
          .to_raise(Net::TimeoutError.new('Connection timeout'))

        result = service.update_weather_summary
        expect(result).to start_with('Weather error:')
        expect(result.length).to be <= 255
      end
    end

    context 'when Home Assistant is mocked' do
      before do
        allow(GlitchCube.config).to receive(:mock_home_assistant?).and_return(true)
      end

      it 'returns unavailable message' do
        result = service.update_weather_summary
        expect(result).to eq('HA unavailable')
      end
    end
  end

  describe '#truncate_summary' do
    it 'returns summary unchanged if under 255 characters' do
      short_summary = 'Currently sunny and 85°F with light winds.'
      result = service.send(:truncate_summary, short_summary)
      expect(result).to eq(short_summary)
    end

    it 'truncates at sentence boundary when possible' do
      long_summary = 'A' * 200 + '. ' + 'B' * 100
      result = service.send(:truncate_summary, long_summary)
      expect(result).to end_with('.')
      expect(result.length).to be <= 255
    end

    it 'truncates at word boundary when no sentence boundary available' do
      long_summary = 'A' * 250 + ' final word here'
      result = service.send(:truncate_summary, long_summary)
      expect(result).to end_with('...')
      expect(result.length).to be <= 255
    end
  end

  describe '#extract_weather_data' do
    it 'extracts weather information from HA states' do
      result = service.send(:extract_weather_data, mock_ha_states)
      
      expect(result).to include(
        temperature: 85.5,
        humidity: 45,
        pressure: 30.2,
        wind_speed: 8.5,
        wind_direction: 180,
        weather_condition: 'sunny',
        location: anything
      )
      expect(result[:forecast]).to be_an(Array)
    end

    it 'handles missing or invalid sensor data' do
      states_with_unavailable = [
        {
          'entity_id' => 'sensor.outdoor_temperature',
          'state' => 'unavailable',
          'attributes' => {}
        },
        {
          'entity_id' => 'sensor.outdoor_humidity', 
          'state' => 'unknown',
          'attributes' => {}
        }
      ]

      result = service.send(:extract_weather_data, states_with_unavailable)
      expect(result[:temperature]).to be_nil
      expect(result[:humidity]).to be_nil
    end
  end

  describe 'integration with real APIs', :integration do
    # These tests will be skipped unless INTEGRATION_TESTS env var is set
    before do
      skip unless ENV['INTEGRATION_TESTS']
    end

    it 'can fetch real weather data and generate summary' do
      # This will make real API calls and record them with VCR
      result = service.update_weather_summary
      
      expect(result).to be_a(String)
      expect(result.length).to be <= 255
      
      # Should contain reasonable weather information
      expect(result).not_to be_empty
      expect(result).not_to eq('Weather data unavailable')
    end
  end
end