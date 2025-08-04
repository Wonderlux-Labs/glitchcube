# Home Assistant API Endpoints for Glitch Cube

This document outlines the specific Home Assistant REST API endpoints that the Glitch Cube will call directly from the Ruby/Sinatra backend.

## Authentication

All API calls require an authorization header:
```
Authorization: Bearer YOUR_LONG_LIVED_ACCESS_TOKEN
```

## Core API Endpoints

### 1. Voice Assistant / Conversation Processing

**Process a text conversation through the voice assistant:**
```http
POST /api/conversation/process
Content-Type: application/json
Authorization: Bearer YOUR_TOKEN

{
  "text": "Turn on the lights",
  "conversation_id": "optional-conversation-id",
  "language": "en"
}
```

**Response:**
```json
{
  "response": {
    "speech": {
      "plain": {
        "speech": "I've turned on the lights for you"
      }
    },
    "card": {},
    "language": "en",
    "response_type": "action_done"
  },
  "conversation_id": "1234567890"
}
```

### 2. Sensor Data

**Get all entity states (includes all sensors):**
```http
GET /api/states
Authorization: Bearer YOUR_TOKEN
```

**Get specific sensor state:**
```http
GET /api/states/{entity_id}
Authorization: Bearer YOUR_TOKEN

Example: GET /api/states/sensor.temperature
```

**Response:**
```json
{
  "entity_id": "sensor.temperature",
  "state": "22.5",
  "attributes": {
    "unit_of_measurement": "°C",
    "friendly_name": "Temperature",
    "device_class": "temperature"
  },
  "last_changed": "2025-08-03T12:00:00+00:00",
  "last_updated": "2025-08-03T12:00:00+00:00"
}
```

### 3. Light Control

**Turn on lights:**
```http
POST /api/services/light/turn_on
Content-Type: application/json
Authorization: Bearer YOUR_TOKEN

{
  "entity_id": "light.glitch_cube",
  "brightness": 255,
  "rgb_color": [255, 0, 128],
  "transition": 2
}
```

**Turn off lights:**
```http
POST /api/services/light/turn_off
Content-Type: application/json
Authorization: Bearer YOUR_TOKEN

{
  "entity_id": "light.glitch_cube",
  "transition": 2
}
```

**Toggle lights:**
```http
POST /api/services/light/toggle
Content-Type: application/json
Authorization: Bearer YOUR_TOKEN

{
  "entity_id": "light.glitch_cube"
}
```

### 4. Script Execution

**Call a Home Assistant script:**
```http
POST /api/services/script/{script_name}
Content-Type: application/json
Authorization: Bearer YOUR_TOKEN

{
  "variables": {
    "message": "Hello from Glitch Cube",
    "duration": 30
  }
}
```

Example scripts:
- `script.welcome_visitor` - Play welcome sequence
- `script.capture_moment` - Take photo and process
- `script.mood_lighting` - Set ambient lighting
- `script.emergency_mode` - Activate emergency lighting

### 5. Camera Integration

**Get camera snapshot:**
```http
GET /api/camera_proxy/{entity_id}
Authorization: Bearer YOUR_TOKEN

Example: GET /api/camera_proxy/camera.glitch_cube
```

Returns the current camera image as binary data.

**Alternative using service:**
```http
POST /api/services/camera/snapshot
Content-Type: application/json
Authorization: Bearer YOUR_TOKEN

{
  "entity_id": "camera.glitch_cube",
  "filename": "/config/www/snapshots/capture_{{ now().timestamp() }}.jpg"
}
```

### 6. Text-to-Speech (TTS)

**Generate speech from text:**
```http
POST /api/services/tts/speak
Content-Type: application/json
Authorization: Bearer YOUR_TOKEN

{
  "entity_id": "tts.google_translate_say",
  "message": "Hello, I am Glitch Cube!",
  "language": "en",
  "options": {
    "cache": true
  }
}
```

**Play TTS on specific media player:**
```http
POST /api/services/tts/google_translate_say
Content-Type: application/json
Authorization: Bearer YOUR_TOKEN

{
  "entity_id": "media_player.glitch_cube_speaker",
  "message": "Welcome to the art installation!",
  "language": "en"
}
```

### 7. Media Player Control

**Play audio file:**
```http
POST /api/services/media_player/play_media
Content-Type: application/json
Authorization: Bearer YOUR_TOKEN

{
  "entity_id": "media_player.glitch_cube_speaker",
  "media_content_id": "http://example.com/audio.mp3",
  "media_content_type": "audio/mpeg"
}
```

**Set volume:**
```http
POST /api/services/media_player/volume_set
Content-Type: application/json
Authorization: Bearer YOUR_TOKEN

{
  "entity_id": "media_player.glitch_cube_speaker",
  "volume_level": 0.7
}
```

### 8. Input Helpers

**Set input text value:**
```http
POST /api/services/input_text/set_value
Content-Type: application/json
Authorization: Bearer YOUR_TOKEN

{
  "entity_id": "input_text.glitch_cube_status",
  "value": "conversing"
}
```

**Toggle input boolean:**
```http
POST /api/services/input_boolean/toggle
Content-Type: application/json
Authorization: Bearer YOUR_TOKEN

{
  "entity_id": "input_boolean.visitor_present"
}
```

### 9. Notifications

**Send notification to log:**
```http
POST /api/services/notify/art_installation_log
Content-Type: application/json
Authorization: Bearer YOUR_TOKEN

{
  "message": "Glitch Cube interaction started",
  "data": {
    "timestamp": "2025-08-03T12:00:00Z",
    "visitor_id": "visitor_123"
  }
}
```

### 10. System Information

**Get Home Assistant configuration:**
```http
GET /api/config
Authorization: Bearer YOUR_TOKEN
```

**Get error log entries:**
```http
GET /api/error_log
Authorization: Bearer YOUR_TOKEN
```

## Ruby Implementation Examples

### Basic API Client

```ruby
require 'httparty'

class HomeAssistantClient
  include HTTParty
  
  def initialize(base_url, token)
    @base_url = base_url
    @headers = {
      'Authorization' => "Bearer #{token}",
      'Content-Type' => 'application/json'
    }
  end
  
  def get_sensor(entity_id)
    self.class.get(
      "#{@base_url}/api/states/#{entity_id}",
      headers: @headers
    )
  end
  
  def call_service(domain, service, data = {})
    self.class.post(
      "#{@base_url}/api/services/#{domain}/#{service}",
      headers: @headers,
      body: data.to_json
    )
  end
  
  def set_light(entity_id, brightness: nil, rgb_color: nil, transition: 2)
    data = {
      entity_id: entity_id,
      transition: transition
    }
    data[:brightness] = brightness if brightness
    data[:rgb_color] = rgb_color if rgb_color
    
    call_service('light', 'turn_on', data)
  end
  
  def speak(message, entity_id: 'media_player.glitch_cube_speaker')
    call_service('tts', 'google_translate_say', {
      entity_id: entity_id,
      message: message,
      language: 'en'
    })
  end
  
  def run_script(script_name, variables = {})
    call_service('script', script_name, variables)
  end
  
  def process_conversation(text, conversation_id: nil)
    data = { text: text }
    data[:conversation_id] = conversation_id if conversation_id
    
    self.class.post(
      "#{@base_url}/api/conversation/process",
      headers: @headers,
      body: data.to_json
    )
  end
end
```

### Integration in Sinatra App

```ruby
# In app.rb or a helper module
helpers do
  def home_assistant
    @home_assistant ||= HomeAssistantClient.new(
      ENV['HOME_ASSISTANT_URL'],
      ENV['HOME_ASSISTANT_TOKEN']
    )
  end
  
  def check_all_sensors
    sensors = %w[
      sensor.battery_level
      sensor.temperature
      sensor.humidity
      sensor.light_level
      binary_sensor.motion_detected
      sensor.sound_level
    ]
    
    sensor_data = {}
    sensors.each do |sensor_id|
      response = home_assistant.get_sensor(sensor_id)
      if response.success?
        data = JSON.parse(response.body)
        sensor_data[sensor_id] = {
          state: data['state'],
          attributes: data['attributes']
        }
      end
    end
    
    sensor_data
  end
  
  def set_mood_lighting(mood)
    case mood
    when 'happy'
      home_assistant.set_light('light.glitch_cube', 
        brightness: 255, 
        rgb_color: [255, 200, 0]
      )
    when 'thinking'
      home_assistant.set_light('light.glitch_cube', 
        brightness: 128, 
        rgb_color: [0, 100, 255]
      )
    when 'excited'
      home_assistant.run_script('breathing_light_effect', {
        color: [255, 0, 128],
        duration: 30
      })
    end
  end
end

# Example endpoint
post '/api/v1/home_assistant_test' do
  # Get sensor data
  sensors = check_all_sensors
  
  # Process through voice assistant
  response = home_assistant.process_conversation("The temperature is #{sensors['sensor.temperature'][:state]}")
  
  # Set mood lighting
  set_mood_lighting('happy')
  
  # Speak response
  home_assistant.speak("I'm feeling great! The temperature is perfect.")
  
  json({
    success: true,
    sensors: sensors,
    conversation_response: JSON.parse(response.body)
  })
end
```

## Error Handling

```ruby
def safe_ha_call(&block)
  begin
    response = yield
    if response.success?
      JSON.parse(response.body)
    else
      log_ha_error(response)
      nil
    end
  rescue StandardError => e
    logger.error "Home Assistant API error: #{e.message}"
    nil
  end
end

def log_ha_error(response)
  logger.error "HA API Error: #{response.code} - #{response.body}"
end
```

## WebSocket API (Advanced)

For real-time updates, Home Assistant also provides a WebSocket API:

```ruby
require 'websocket-client-simple'

def connect_ha_websocket
  ws = WebSocket::Client::Simple.connect "ws://#{HA_HOST}:8123/api/websocket"
  
  ws.on :open do
    # Authenticate
    ws.send({ type: 'auth', access_token: HA_TOKEN }.to_json)
  end
  
  ws.on :message do |msg|
    data = JSON.parse(msg.data)
    case data['type']
    when 'auth_ok'
      # Subscribe to events
      ws.send({
        id: 1,
        type: 'subscribe_events',
        event_type: 'state_changed'
      }.to_json)
    when 'event'
      handle_state_change(data['event'])
    end
  end
  
  ws
end
```

## Rate Limiting

Home Assistant has built-in rate limiting. Be mindful of:
- API calls are limited to 100 requests per minute by default
- WebSocket connections are limited to 5 per IP
- Large responses (like all states) should be cached when possible

## Security Notes

1. Always use HTTPS in production
2. Store the long-lived access token securely (use environment variables)
3. Create a dedicated user for the Glitch Cube with minimal permissions
4. Consider implementing request signing for additional security
5. Log all API interactions for debugging and security auditing