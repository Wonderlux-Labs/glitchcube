# Weather summarization service using Home Assistant data and Gemini Flash Lite
class WeatherService
  include HTTParty
  
  # Home Assistant API configuration
  base_uri GlitchCube.config.home_assistant.url
  
  def initialize
    @ha_token = GlitchCube.config.home_assistant.token
    @openrouter_client = OpenRouter::Client.new(
      access_token: GlitchCube.config.openrouter_api_key
    )
  end
  
  # Main method to get and summarize weather
  def update_weather_summary
    return "HA unavailable" if GlitchCube.config.mock_home_assistant?
    
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
    headers = {
      'Authorization' => "Bearer #{@ha_token}",
      'Content-Type' => 'application/json'
    }
    
    # Get all states from Home Assistant
    response = self.class.get('/api/states', headers: headers, timeout: 10)
    return {} unless response.success?
    
    states = response.parsed_response
    weather_sensors = extract_weather_data(states)
    
    weather_sensors
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
      location: GlitchCube.config.installation_location || "Unknown"
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
    
    response = @openrouter_client.complete(
      model: 'google/gemini-2.0-flash-thinking-exp:free',
      messages: [
        {
          role: 'user',
          content: prompt
        }
      ],
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
  
  # Update the Home Assistant weather sensor via webhook
  def update_home_assistant_sensor(summary)
    webhook_url = "#{GlitchCube.config.home_assistant.url}/api/webhook/glitchcube_weather"
    
    HTTParty.post(webhook_url, {
      body: { weather: summary }.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: 5
    })
  rescue => e
    # Log error but don't fail the whole operation
    puts "Failed to update HA weather sensor: #{e.message}"
  end
end