# Weather summarization service using Home Assistant data and Gemini Flash Lite
require_relative 'openrouter_service'

class WeatherService
  def initialize
    @ha_client = HomeAssistantClient.new
  end
  
  # Main method to get and summarize weather
  def update_weather_summary
    return "HA unavailable" if GlitchCube.config.home_assistant.mock_enabled
    
    weather_data = fetch_weather_sensors
    return "No weather data" if weather_data.empty?
    
    summary = generate_weather_summary(weather_data)
    truncated_summary = truncate_summary(summary)
    
    update_home_assistant_sensor(truncated_summary)
    truncated_summary
  rescue => e
    error_message = "Weather error: #{e.message[0..50]}"
    update_home_assistant_sensor(error_message)
    error_message
  end
  
  private
  
  # Fetch weather-related sensor data from Home Assistant
  def fetch_weather_sensors
    states = @ha_client.states
    return {} if states.empty?
    
    extract_weather_data(states)
  end
  
  # Extract weather-related information from HA states
  def extract_weather_data(states)
    weather_data = {
      temperature: nil,
      humidity: nil,
      pressure: nil,
      wind_speed: nil,
      wind_direction: nil,
      weather_condition: nil,
      forecast: nil,
      location: GlitchCube.config.device.location || "Unknown"
    }
    
    states.each do |state|
      entity_id = state['entity_id']
      state_value = state['state']
      attributes = state['attributes'] || {}
      
      case entity_id
      when /weather\./
        # Weather entity (comprehensive weather data)
        weather_data[:temperature] = attributes['temperature']
        weather_data[:humidity] = attributes['humidity']
        weather_data[:pressure] = attributes['pressure']
        weather_data[:wind_speed] = attributes['wind_speed']
        weather_data[:wind_direction] = attributes['wind_bearing']
        weather_data[:weather_condition] = state_value
        weather_data[:forecast] = attributes['forecast']&.first(3) # Next 3 periods
      when /sensor.*temperature/
        # Temperature sensors
        if state_value != 'unknown' && state_value != 'unavailable'
          weather_data[:temperature] ||= state_value.to_f
        end
      when /sensor.*humidity/
        # Humidity sensors
        if state_value != 'unknown' && state_value != 'unavailable'
          weather_data[:humidity] ||= state_value.to_f
        end
      when /sensor.*pressure/
        # Pressure sensors
        if state_value != 'unknown' && state_value != 'unavailable'
          weather_data[:pressure] ||= state_value.to_f
        end
      end
    end
    
    # Remove nil values
    weather_data.compact
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
    
    response.dig('choices', 0, 'message', 'content')&.strip || "Summary unavailable"
  end
  
  # Build the prompt for weather summarization
  def build_weather_prompt(weather_data)
    data_summary = weather_data.map do |key, value|
      case key
      when :forecast
        if value.is_a?(Array) && !value.empty?
          forecast_items = value.map do |f|
            "#{f['datetime']}: #{f['condition']} #{f['temperature']}°"
          end.join(", ")
          "forecast: #{forecast_items}"
        end
      else
        "#{key}: #{value}"
      end
    end.compact.join(", ")
    
    <<~PROMPT
      Summarize this weather data in exactly one sentence under 200 characters for an art installation in the desert. Be conversational and mention key details people would care about:
      
      #{data_summary}
      
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
  rescue => e
    # Log error but don't fail the whole operation
    puts "Failed to update HA weather sensor: #{e.message}"
  end
end