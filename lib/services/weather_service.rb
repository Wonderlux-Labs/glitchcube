# frozen_string_literal: true

# Weather summarization service using Home Assistant data and Gemini Flash Lite
require_relative 'openrouter_service'

class WeatherService
  def initialize
    @ha_client = HomeAssistantClient.new
  end

  # Main method to get and summarize weather
  def update_weather_summary
    # Check if HA is configured
    return 'HA unavailable' unless GlitchCube.config.home_assistant.url && GlitchCube.config.home_assistant.token

    weather_data = fetch_weather_sensors
    return 'No weather data' if weather_data.empty?

    summary = generate_weather_summary(weather_data)
    truncated_summary = truncate_summary(summary)

    update_home_assistant_sensor(truncated_summary)
    truncated_summary
  rescue StandardError => e
    error_message = "Weather error: #{e.message[0..50]}"
    update_home_assistant_sensor(error_message)
    error_message
  end

  private

  # Fetch weather data from the Playa Weather API sensor
  def fetch_weather_sensors
    states = @ha_client.states
    playa_weather_state = states.find { |state| state['entity_id'] == 'sensor.playa_weather_api' }
    return {} if playa_weather_state.nil?

    attributes = playa_weather_state['attributes'] || {}
    weather_data_json = attributes['weather_data']

    return {} if weather_data_json.nil? || weather_data_json.empty?

    begin
      weather_data = JSON.parse(weather_data_json)
      # Add location info
      weather_data['location'] = GlitchCube.config.device.location || 'Black Rock City'
      weather_data
    rescue JSON::ParserError => e
      puts "Error parsing Playa Weather API data: #{e.message}"
      {}
    end
  end

  # Generate weather summary using Gemini Flash Lite
  def generate_weather_summary(weather_data)
    prompt = build_weather_prompt(weather_data)

    response = OpenRouterService.complete(
      prompt,
      model: 'google/gemini-2.0-flash-thinking-exp:free',
      max_tokens: 100,
      temperature: 0.3
    )

    response.dig('choices', 0, 'message', 'content')&.strip || 'Summary unavailable'
  end

  # Build the prompt for weather summarization
  def build_weather_prompt(weather_data)
    # Convert the full JSON to a string for the LLM to parse
    weather_json_string = weather_data.to_json

    <<~PROMPT
      Summarize this weather data in exactly one sentence under 200 characters for an art installation in the desert. Be conversational and mention key details people would care about (current temp, conditions, wind, what to expect). Include forecast info if relevant:

      #{weather_json_string}

      Example style: "Currently 85°F and sunny with light winds. Expect cooler evening temps around 65°F with clear skies perfect for stargazing."

      Your summary:
    PROMPT
  end

  # Truncate summary to fit Home Assistant text input limit
  def truncate_summary(summary)
    return summary if summary.length <= 255

    # Try to truncate at sentence boundary
    truncated = summary[0..251]
    last_period = truncated.rindex('.')

    if last_period && last_period > 200
      truncated[0..last_period]
    else
      # Truncate at word boundary
      truncated = summary[0..251]
      last_space = truncated.rindex(' ')
      if last_space && last_space > 200
        "#{truncated[0..last_space].strip}..."
      else
        "#{summary[0..252]}..."
      end
    end
  end

  # Update the Home Assistant weather sensor directly
  def update_home_assistant_sensor(summary)
    @ha_client.set_state('input_text.current_weather', summary)
  rescue StandardError => e
    # Log error but don't fail the whole operation
    puts "Failed to update HA weather sensor: #{e.message}"
  end
end
