# Home Assistant Entities

⚠️ **Status**: Home Assistant not currently accessible
Generated on: 2025-08-07 09:30:00
Last known configuration

## Entity Summary by Domain

### Core Entities Required:
- **automation**: Movement tracking, weather updates, camera vision
- **binary_sensor**: Motion detection, camera motion
- **camera**: Tablet camera for vision analysis
- **input_text**: Weather summary, camera analysis, persona, environment
- **input_number**: GPS coordinates (lat/lng/prev_lat/prev_lng)
- **sensor**: Weather data, vision status, people count
- **weather**: OpenWeatherMap integration

## Glitch Cube Integration Status

### Weather System Entities:
- ✅ **weather.openweathermap** - Primary weather data source
- ✅ **sensor.playa_weather_api** - Template sensor with aggregated weather data
- ✅ **input_text.current_weather** - Stores LLM-summarized weather (255 char max)
- ✅ **sensor.openweathermap_temperature** - Current temperature
- ✅ **sensor.openweathermap_feels_like_temperature** - Feels like temperature
- ✅ **sensor.openweathermap_condition** - Current conditions
- ✅ **sensor.openweathermap_humidity** - Humidity percentage
- ✅ **sensor.openweathermap_wind_speed** - Wind speed
- ✅ **sensor.openweathermap_wind_bearing** - Wind direction
- ✅ **sensor.openweathermap_uv_index** - UV index
- ✅ **sensor.openweathermap_cloud_coverage** - Cloud coverage percentage

### Camera Vision System Entities:
- ✅ **camera.tablet** - Physical camera entity
- ✅ **binary_sensor.camera_motion** - Motion detection trigger
- ✅ **input_text.camera_vision_analysis** - Stores vision analysis (255 char max)
- ✅ **sensor.camera_vision_status** - Status (idle/people_detected/activity_detected)
- ✅ **sensor.camera_people_count** - Extracted people count

### GPS/Location System Entities:
- ⚠️ **device_tracker.glitch_cube** - GPS device tracker (needs configuration)
- ✅ **input_number.glitch_cube_lat** - Current latitude
- ✅ **input_number.glitch_cube_lng** - Current longitude  
- ✅ **input_number.glitch_cube_prev_lat** - Previous latitude for movement detection
- ✅ **input_number.glitch_cube_prev_lng** - Previous longitude for movement detection

### Conversation System Entities:
- ✅ **input_text.current_persona** - Active AI persona
- ✅ **input_text.current_environment** - Environment description
- ✅ **input_text.glitchcube_host** - Glitch Cube host IP

### Automations:
- ✅ **automation.camera_motion_vision_analysis** - Triggers vision on motion
- ✅ **automation.clear_camera_vision_analysis** - Clears after 5min inactivity
- ✅ **automation.update_weather_summary** - Periodic weather updates
- ✅ **automation.update_previous_coordinates** - GPS movement tracking

### Scripts:
- ✅ **script.analyze_camera_now** - Manual camera analysis trigger
- ✅ **script.analyze_camera_with_prompt** - Custom prompt analysis

## Weather Data Structure

The `sensor.playa_weather_api` template sensor aggregates weather data in JSON format:

```json
{
  "timestamp": "ISO8601 timestamp",
  "location": "Black Rock City",
  "current": {
    "temperature": 85.0,
    "feels_like": 88.0,
    "condition": "sunny",
    "weather_code": 800,
    "humidity": 15.0,
    "pressure": 1013.0,
    "dew_point": 35.0,
    "visibility": 10.0,
    "uv_index": 9.0,
    "cloud_coverage": 5.0,
    "wind_speed": 12.0,
    "wind_bearing": 270.0,
    "precipitation": {
      "rain": 0.0,
      "snow": 0.0,
      "kind": "none"
    }
  },
  "daily_forecast": [...],
  "hourly_forecast": [...]
}
```

## Integration with Ruby Application

### Weather Service (`lib/services/weather_service.rb`)
```ruby
# Fetches weather data from sensor.playa_weather_api
weather_data = @ha_client.states.find { |s| s['entity_id'] == 'sensor.playa_weather_api' }
attributes = weather_data['attributes']
weather_json = JSON.parse(attributes['weather_data'])

# Summarizes with LLM
summary = generate_weather_summary(weather_json)

# Stores in input_text.current_weather
@ha_client.set_state('input_text.current_weather', summary)
```

### Camera Vision Access
```ruby
# Get current analysis
analysis = @ha_client.get_state('input_text.camera_vision_analysis')
people_count = @ha_client.get_state('sensor.camera_people_count')

# Trigger manual analysis
@ha_client.call_service('script', 'analyze_camera_now')
```

### GPS Tracking
```ruby
# Get current position
lat = @ha_client.get_state('input_number.glitch_cube_lat')
lng = @ha_client.get_state('input_number.glitch_cube_lng')

# Update position
@ha_client.set_state('input_number.glitch_cube_lat', new_lat)
@ha_client.set_state('input_number.glitch_cube_lng', new_lng)
```

## Configuration Files

### Weather Template Sensor
`config/homeassistant/template/playa_weather_api.yaml`
- Updates every 15 minutes
- Aggregates OpenWeatherMap data
- Includes forecasts

### Camera Vision Automation
`config/homeassistant/automations/camera_vision_analysis.yaml`
- Triggers on motion detection
- 60-second cooldown
- Stores in input_text

### Input Helpers
`config/homeassistant/input_helpers/input_text.yaml`
- current_weather (255 chars)
- camera_vision_analysis (255 chars)
- current_persona (100 chars)
- current_environment (255 chars)

## Required Home Assistant Integrations

1. **OpenWeatherMap** - Weather data provider
2. **LLM Vision** - Camera analysis (provider: 01K21T5563YK72553SX49G9WK3)
3. **Fully Kiosk Browser** - Tablet camera access
4. **RESTful** - API endpoints for Glitch Cube

## Troubleshooting

### Weather Not Updating
1. Check OpenWeatherMap API key is valid
2. Verify weather.openweathermap entity exists
3. Check template sensor automation is enabled
4. Review logs for template errors

### Camera Vision Not Working
1. Verify camera.tablet is accessible
2. Check LLM Vision integration is configured
3. Ensure motion sensor is triggering
4. Check automation cooldown period

### GPS Not Tracking
1. Create device_tracker.glitch_cube entity
2. Configure input_number helpers for coordinates
3. Enable movement tracking automation
4. Verify GPS data source

## Next Steps

1. **Configure device_tracker.glitch_cube** for real GPS tracking
2. **Set up OpenWeatherMap** with API key for weather data
3. **Test camera motion detection** with binary_sensor.camera_motion
4. **Verify LLM Vision provider** configuration
5. **Test weather summarization** with manual trigger