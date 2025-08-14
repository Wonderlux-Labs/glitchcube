# Home Assistant Integration Guide

This guide provides complete Home Assistant configuration and integration patterns for the Glitch Cube interactive art installation. Home Assistant handles physical interfaces (microphones, speakers, cameras, sensors) while the Sinatra app provides AI intelligence and artistic responses.

## Architecture Overview

```
[Visitor] 
    ↓ (voice)
[HASS Voice Assistant] 
    ↓ (STT → REST API)
[Glitch Cube Sinatra App] 
    ↓ (AI Response → TTS/MP3)
[HASS Audio Output]
    ↓ (artistic response)
[Visitor Experience]
```

## Core Home Assistant Configuration

### configuration.yaml

```yaml
# configuration.yaml
homeassistant:
  name: "Glitch Cube Installation"
  latitude: !secret latitude
  longitude: !secret longitude
  elevation: !secret elevation
  unit_system: metric
  time_zone: !secret time_zone
  
# Enable REST API
api:
  
# Enable frontend
frontend:
  
# Enable configuration UI
config:

# Text to speech
tts:
  - platform: google_translate
    service_name: google_say
    language: 'en'
    cache: true
    cache_dir: /tmp/tts
    time_memory: 300

# Speech to text
stt:
  - platform: whisper
    model: base
    language: en

# Voice assistant
voice_assistant:
  - id: glitch_cube_assistant
    name: "Glitch Cube Voice"
    conversation_engine: conversation.glitch_cube
    stt_engine: stt.whisper
    tts_engine: tts.google_say
    wake_word_engine: openwakeword
    wake_word: "hey_cube"
    noise_suppression_level: 2
    auto_gain: 31dBFS
    volume_multiplier: 1.0

# Conversation integration
conversation:
  - id: glitch_cube
    name: "Glitch Cube Conversation"

# HTTP integration for REST API calls
http:
  server_port: 8123
  cors_allowed_origins:
    - "http://localhost:4567"
    - "https://your-glitch-cube.com"

# Camera integration
camera:
  - platform: generic
    name: "Cube Camera"
    still_image_url: "http://192.168.1.100/snapshot"
    stream_source: "rtsp://192.168.1.100:554/stream"
    verify_ssl: false
    
  - platform: local_file
    name: "Last Captured Image"
    file_path: /config/www/last_capture.jpg

# Input helpers for state management
input_text:
  installation_status:
    name: "Installation Status"
    initial: "idle"
    max: 50
    
  current_persona:
    name: "Current Persona"
    initial: "BUDDY"
    max: 20
    
  camera_vision_analysis:
    name: "Camera Vision Analysis"
    max: 1000

input_boolean:
  voice_interaction_active:
    name: "Voice Interaction Active"
    initial: false
    
  motion_detection_enabled:
    name: "Motion Detection Enabled"
    initial: true
    
  motion_detected:
    name: "Motion Detected"
    initial: false
    
  human_detected:
    name: "Human Detected"
    initial: false
    
  cube_is_moving:
    name: "Cube Is Moving"
    initial: false

input_number:
  interaction_timeout:
    name: "Interaction Timeout (seconds)"
    min: 10
    max: 300
    step: 10
    initial: 60

# Timers
timer:
  interaction_session:
    name: "Interaction Session Timer"
    duration: "00:01:00"
    restore: true
```

### secrets.yaml

```yaml
# secrets.yaml
latitude: 40.7128
longitude: -74.0060
elevation: 10
time_zone: "America/New_York"

# Glitch Cube app configuration
glitch_cube_url: "http://your-glitch-cube.com:4567"
glitch_cube_api_key: "your-api-key-here"

# Camera credentials
camera_username: "admin"
camera_password: "password123"
```

## Entity Reference

### Motion Detection Entities

#### Primary Motion Sensor
- **Entity ID**: `input_boolean.motion_detected`
- **Type**: Input Boolean (switch)
- **Description**: Main motion detection sensor for the Glitch Cube
- **Used By**:
  - Camera vision analysis automation
  - Sensor update webhook
  - Reset all sensors script

#### Human Detection
- **Entity ID**: `input_boolean.human_detected`
- **Type**: Input Boolean
- **Description**: Indicates if a human has been detected

### Movement & Position Entities
- `input_boolean.cube_is_moving` - Cube is currently moving
- `input_boolean.cube_stopped_moving` - Cube just stopped moving
- `input_boolean.cube_tilted` - Cube is tilted
- `input_boolean.cube_stable` - Cube is stable (default: true)

### Camera Entities

#### Camera Stream
- **Entity ID**: `camera.camera`
- **Type**: Camera
- **Description**: Main camera feed for vision analysis

#### Vision Analysis Storage
- **Entity ID**: `input_text.camera_vision_analysis`
- **Type**: Input Text
- **Description**: Stores the latest LLM vision analysis result

#### Vision Status Sensor
- **Entity ID**: `sensor.camera_vision_status`
- **Type**: Template Sensor
- **States**: `idle`, `people_detected`, `activity_detected`
- **Attributes**:
  - `analysis_text` - The full analysis text
  - `last_analysis` - Timestamp of last analysis
  - `people_detected` - Boolean if people detected
  - `motion_active` - Current motion state

### Lighting Entities

#### Voice Ring Light
- **Entity ID**: `light.cube_voice_ring`
- **Type**: Light
- **Description**: Ring light on the voice assistant that shows system status
- **Status Colors**:
  - **Blue**: Home Assistant connected, Sinatra not connected
  - **Green**: Full system operational (HA + Sinatra connected)
  - **Red/Error**: System errors

#### Other Lights
- `light.cube_light` - Main cube lighting
- `light.cart_light` - Cart ambient lighting  
- `light.awtrix_b85e20_matrix` - Matrix display
- `light.awtrix_b85e20_indicator_1` - Status indicator 1
- `light.awtrix_b85e20_indicator_2` - Status indicator 2
- `light.awtrix_b85e20_indicator_3` - Status indicator 3

## Integration Points

### Sinatra ↔ Home Assistant Communication

#### 1. Health Monitoring Flow
- **GET /health** - Returns circuit breaker status (`healthy` or `degraded`)
- **GET /health/push** - Reads HA's `sensor.health_monitoring` and optionally pushes to Uptime Kuma

#### 2. Home Assistant → Sinatra Monitoring
- **sensor.glitchcube_api_health** - REST sensor polling `/health` every 30s
  - Returns: `healthy`, `degraded`, or `unknown`

#### 3. Webhook Communications

**Sinatra → Home Assistant**
- **Webhook URL**: `http://homeassistant.local:8123/api/webhook/glitchcube_update`
- **Service**: `Services::HomeAssistantWebhookService` 
- **Updates**:
  - `input_text.current_environment` - Environment name
  - `input_text.current_weather` - Weather status
  - `input_number.avg_sound_db` - Sound level
  - `input_text.current_persona` - Active persona
  - `input_datetime.last_interaction` - Last interaction timestamp

**Home Assistant → Sinatra (Voice Conversations)**
- **Endpoint**: `POST /api/v1/ha_webhook`
- **Purpose**: Home Assistant voice assistant integration
- **Event Types**: `conversation_started`, `conversation_ended`

## Voice Assistant Integration

### Voice Conversation Handler

```yaml
# automations.yaml - Voice Interaction Automation
- id: voice_interaction_handler
  alias: "Voice Interaction Handler"
  description: "Handle voice interactions with Glitch Cube"
  trigger:
    - platform: event
      event_type: voice_assistant_speech_finished
      event_data:
        assistant_id: glitch_cube_assistant
  condition:
    - condition: state
      entity_id: sensor.glitchcube_api_health
      state: "healthy"
  action:
    - service: input_boolean.turn_on
      target:
        entity_id: input_boolean.voice_interaction_active
    - service: timer.start
      target:
        entity_id: timer.interaction_session
    - service: script.process_voice_input
      data:
        speech_text: "{{ trigger.event.data.speech_text }}"
        session_id: "{{ trigger.event.data.session_id | default(now().timestamp()) }}"
```

### Voice Processing Script

```yaml
# scripts.yaml
process_voice_input:
  alias: "Process Voice Input with Glitch Cube"
  description: "Send voice input to Glitch Cube app and handle response"
  fields:
    speech_text:
      description: "The transcribed speech text"
      example: "Create a beautiful sunset painting"
    session_id:
      description: "Unique session identifier"
      example: "session_123456"
  sequence:
    - service: notify.installation_log
      data:
        message: "Voice input received: {{ speech_text }}"
    
    # Send to Glitch Cube app
    - service: rest_command.send_conversation_to_glitch_cube
      data:
        message: "{{ speech_text }}"
        session_id: "{{ session_id }}"
        context:
          source: "voice_assistant"
          timestamp: "{{ now().isoformat() }}"
    
    # Wait for response and handle it
    - wait_template: "{{ states('sensor.glitch_cube_last_response_id') != 'unknown' }}"
      timeout: "00:00:30"
      continue_on_timeout: true
    
    - choose:
        - conditions:
            - condition: template
              value_template: "{{ wait.completed }}"
        sequence:
          - service: script.handle_glitch_cube_response
            data:
              response_data: "{{ state_attr('sensor.glitch_cube_last_response', 'response_data') }}"
      default:
        - service: tts.google_say
          data:
            message: "I'm sorry, I'm having trouble processing your request right now. Please try again."
```

## REST API Configuration

### REST Commands for Glitch Cube Communication

```yaml
# configuration.yaml - REST Commands
rest_command:
  send_conversation_to_glitch_cube:
    url: "{{ glitch_cube_url }}/api/v1/conversation"
    method: POST
    headers:
      Content-Type: "application/json"
      Authorization: "Bearer {{ glitch_cube_api_key }}"
    payload: >
      {
        "message": "{{ message }}",
        "session_id": "{{ session_id }}",
        "context": {{ context | tojson }},
        "source": "home_assistant"
      }
    timeout: 30

  send_image_to_glitch_cube:
    url: "{{ glitch_cube_url }}/api/v1/upload_image"
    method: POST
    headers:
      Authorization: "Bearer {{ glitch_cube_api_key }}"
    payload: "{{ image_data }}"
    content_type: "multipart/form-data"
    timeout: 60

  send_sensor_data_to_glitch_cube:
    url: "{{ glitch_cube_url }}/api/v1/sensor_data"
    method: POST
    headers:
      Content-Type: "application/json"
      Authorization: "Bearer {{ glitch_cube_api_key }}"
    payload: >
      {
        "sensors": {{ sensor_data | tojson }},
        "timestamp": "{{ now().isoformat() }}"
      }
    timeout: 15
```

## Core REST API Endpoints

### Authentication
All API calls require an authorization header:
```
Authorization: Bearer YOUR_LONG_LIVED_ACCESS_TOKEN
```

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

### 5. Text-to-Speech (TTS)

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

### 6. Camera Integration

**Get camera snapshot:**
```http
GET /api/camera_proxy/{entity_id}
Authorization: Bearer YOUR_TOKEN

Example: GET /api/camera_proxy/camera.glitch_cube
```

## Camera Integration

### Image Capture and Upload

```yaml
# scripts.yaml - Camera handling
capture_and_send_image:
  alias: "Capture and Send Image to Glitch Cube"
  description: "Capture image from camera and send to Glitch Cube app"
  fields:
    request_id:
      description: "Request ID from Glitch Cube app"
    camera_entity:
      description: "Camera entity to capture from"
      default: "camera.cube_camera"
  sequence:
    - service: notify.installation_log
      data:
        message: "Capturing image from {{ camera_entity }} for request {{ request_id }}"
    
    # Capture snapshot
    - service: camera.snapshot
      target:
        entity_id: "{{ camera_entity }}"
      data:
        filename: "/config/www/captures/capture_{{ request_id }}.jpg"
    
    # Wait for file to be written
    - delay: "00:00:02"
    
    # Send to Glitch Cube app
    - service: shell_command.upload_image_to_glitch_cube
      data:
        image_path: "/config/www/captures/capture_{{ request_id }}.jpg"
        request_id: "{{ request_id }}"
    
    # Clean up old captures (keep last 10)
    - service: shell_command.cleanup_old_captures
```

### Vision Analysis Automation

```yaml
# automations.yaml - Camera vision analysis
- id: camera_motion_vision_analysis
  alias: "Camera Motion Vision Analysis"
  description: "Analyze camera feed when motion detected"
  trigger:
    - platform: state
      entity_id: input_boolean.motion_detected
      to: "on"
  action:
    - service: script.capture_and_send_image
      data:
        request_id: "motion_{{ now().timestamp() }}"
        camera_entity: "camera.cube_camera"
    
    # Store analysis result
    - service: input_text.set_value
      target:
        entity_id: input_text.camera_vision_analysis
      data:
        value: "Motion detected at {{ now().strftime('%H:%M:%S') }}"
```

## Error Handling and Recovery

### Error Detection Automations

```yaml
# automations.yaml - Error handling
- id: glitch_cube_app_offline
  alias: "Glitch Cube App Offline Error"
  description: "Handle when Glitch Cube app becomes unavailable"
  trigger:
    - platform: state
      entity_id: sensor.glitchcube_api_health
      to: "unknown"
      for: "00:01:00"
  action:
    - service: script.handle_system_error
      data:
        error_type: "app_offline"
        error_message: "Glitch Cube application is not responding"
        component: "glitch_cube_app"
        severity: "high"
    
    - service: tts.google_say
      data:
        message: "I'm experiencing technical difficulties. Please try again in a few moments."
    
    - service: input_text.set_value
      target:
        entity_id: input_text.installation_status
      data:
        value: "error"
```

### Error Handling Scripts

```yaml
# scripts.yaml - Error handling
handle_system_error:
  alias: "Handle System Error"
  description: "Process and report system errors"
  fields:
    error_type:
      description: "Type of error"
    error_message:
      description: "Error description"
    component:
      description: "Component that failed"
    severity:
      description: "Error severity level"
      default: "medium"
  sequence:
    - service: notify.installation_log
      data:
        message: "ERROR [{{ severity }}]: {{ error_type }} - {{ error_message }} ({{ component }})"
    
    # Report to Glitch Cube app if it's available
    - condition: not
      conditions:
        - condition: state
          entity_id: sensor.glitchcube_api_health
          state: "unknown"
    
    - service: rest_command.report_error_to_glitch_cube
      data:
        error_type: "{{ error_type }}"
        error_message: "{{ error_message }}"
        component: "{{ component }}"
        severity: "{{ severity }}"
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
  
  def speak(message, entity_id: 'media_player.cube_speaker')
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
      home_assistant.set_light('light.cube_light', 
        brightness: 255, 
        rgb_color: [255, 200, 0]
      )
    when 'thinking'
      home_assistant.set_light('light.cube_light', 
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
```

### Error Handling

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

## Testing Integration

### 1. Test Sinatra Health Endpoint
```bash
curl http://localhost:4567/health
# Should return: {"status":"healthy","timestamp":"...","circuit_breakers":[...]}
```

### 2. Test Health Push Endpoint
```bash
curl http://localhost:4567/health/push
# Should return: {"status":"ok","message":"WiFi:-50dBm | Up:2.3d | ..."}
```

### 3. Test Webhook from Sinatra
```bash
curl -X POST http://homeassistant.local:8123/api/webhook/glitchcube_update \
  -H "Content-Type: application/json" \
  -d '{"persona":"BUDDY","interaction":true}'
```

### 4. Verify in Home Assistant
- Check **Developer Tools → States**:
  - `sensor.glitchcube_api_health` should show `healthy`
  - `sensor.health_monitoring` should show consolidated status
  - `input_text.current_persona` should update via webhook

## Security Considerations

1. **Always use HTTPS in production**
2. **Store the long-lived access token securely** (use environment variables)
3. **Create a dedicated user** for the Glitch Cube with minimal permissions
4. **Implement request signing** for additional security
5. **Log all API interactions** for debugging and security auditing

## Rate Limiting

Home Assistant has built-in rate limiting:
- API calls are limited to 100 requests per minute by default
- WebSocket connections are limited to 5 per IP
- Large responses (like all states) should be cached when possible

## Configuration Files Organization

### Core Configuration
- `configuration.yaml` - Main HA configuration
- `automations.yaml` - Main automations file
- `rest_commands.yaml` - REST command definitions

### Modular Configurations
- `automations/*.yaml` - Individual automation files
- `sensors/*.yaml` - REST and other sensors
- `template/*.yaml` - Template sensors
- `input_helpers/*.yaml` - Input helpers

This comprehensive Home Assistant integration provides a complete voice-controlled interface for the Glitch Cube interactive art installation, handling voice interactions, camera capture, sensor monitoring, error reporting, and environmental controls through REST API communications.