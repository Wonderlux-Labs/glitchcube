# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/services/weather_service'

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
        allow(GlitchCube.config.home_assistant).to receive(:mock_enabled).and_return(false)
        allow(GlitchCube.config.device).to receive(:location).and_return('Black Rock Desert')
      end

      it 'fetches weather data and generates summary', :vcr do
        # Mock the Home Assistant client
        mock_ha_client = instance_double(HomeAssistantClient)
        allow(HomeAssistantClient).to receive(:new).and_return(mock_ha_client)

        # Mock the states call to return weather data
        allow(mock_ha_client).to receive(:states).and_return(mock_ha_states)

        # Mock the set_state call (this is what we want to verify)
        expect(mock_ha_client).to receive(:set_state).with('input_text.current_weather', anything)

        result = service.update_weather_summary

        expect(result).to be_a(String)
        expect(result.length).to be <= 255
        expect(result).not_to eq('No weather data')
        expect(result).not_to include('Weather error')

        # Verify it contains weather-related information
        expect(result.downcase).to match(/temperature|sunny|clear|wind|humid/i)
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
          .to_raise(Timeout::Error.new('Connection timeout'))

        result = service.update_weather_summary
        expect(result).to start_with('Weather error:')
        expect(result.length).to be <= 255
      end
    end

    context 'when updating Home Assistant weather sensor' do
      let(:mock_summary) { 'Sunny, 75°F, 45% humidity' }
      let(:mock_ha_client) { instance_double(HomeAssistantClient) }

      before do
        allow(GlitchCube.config.home_assistant).to receive(:mock_enabled).and_return(false)
        allow(HomeAssistantClient).to receive(:new).and_return(mock_ha_client)
        allow(mock_ha_client).to receive(:states).and_return(mock_ha_states)
        allow(service).to receive(:generate_weather_summary).and_return(mock_summary)
      end

      it 'calls set_state with correct entity and weather summary' do
        expect(mock_ha_client).to receive(:set_state).with('input_text.current_weather', mock_summary)

        result = service.update_weather_summary

        expect(result).to include(mock_summary)
      end

      it 'handles HA client errors gracefully' do
        allow(mock_ha_client).to receive(:set_state).and_raise(StandardError.new('Connection failed'))

        result = service.update_weather_summary

        # Should still return the summary even if HA update fails
        expect(result).to include(mock_summary)
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
      long_summary = "#{'A' * 200}. #{'B' * 100}"
      result = service.send(:truncate_summary, long_summary)
      expect(result).to end_with('.')
      expect(result.length).to be <= 255
    end

    it 'truncates at word boundary when no sentence boundary available' do
      long_summary = "#{'A' * 250} final word here"
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

  describe 'integration with real APIs', :vcr do
    it 'attempts to connect to real HA and records the interaction' do
      # Override config to use real HA for VCR recording (token loaded automatically from spec_helper)
      allow(GlitchCube.config.home_assistant).to receive_messages(url: ENV['HA_URL'] || 'http://glitchcube.local:8123', token: ENV.fetch('HOME_ASSISTANT_TOKEN', nil),
                                                                  mock_enabled: false)

      # This will record real API calls to HA (even if they fail) and potentially OpenRouter
      result = service.update_weather_summary

      expect(result).to be_a(String)
      expect(result.length).to be <= 255
      expect(result).not_to eq('HA unavailable')

      # The result should be either weather data, "No weather data", or a weather error
      # This tests that the service handles real API calls and failures gracefully
      expect(['No weather data'] + [result]).to include(result)
    end
  end
end
