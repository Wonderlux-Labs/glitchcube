# Home Assistant + Desiru Interactive Art Installation Integration

**Author:** Manus AI  
**Date:** August 3, 2025  
**Target:** Interactive Art Installation with Voice Control  

## Overview

This guide provides complete Home Assistant configurations and scripts for integrating with a Desiru-powered interactive art installation. The system enables voice-controlled interactions where Home Assistant handles physical interfaces (microphones, speakers, cameras, sensors) while the Desiru app provides AI intelligence and artistic responses.

## Architecture

```
[Visitor] 
    ↓ (voice)
[HASS Voice Assistant] 
    ↓ (STT → REST API)
[Desiru Art App] 
    ↓ (AI Response → TTS/MP3)
[HASS Audio Output]
    ↓ (artistic response)
[Visitor Experience]
```

## Configuration Files

### configuration.yaml

```yaml
# configuration.yaml
homeassistant:
  name: "Interactive Art Installation"
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
  - id: art_installation_assistant
    name: "Art Installation Voice"
    conversation_engine: conversation.art_installation
    stt_engine: stt.whisper
    tts_engine: tts.google_say
    wake_word_engine: openwakeword
    wake_word: "hey_art"
    noise_suppression_level: 2
    auto_gain: 31dBFS
    volume_multiplier: 1.0

# Conversation integration
conversation:
  - id: art_installation
    name: "Art Installation Conversation"

# HTTP integration for REST API calls
http:
  server_port: 8123
  cors_allowed_origins:
    - "http://localhost:4567"
    - "https://your-desiru-app.com"

# Camera integration
camera:
  - platform: generic
    name: "Installation Camera"
    still_image_url: "http://192.168.1.100/snapshot"
    stream_source: "rtsp://192.168.1.100:554/stream"
    verify_ssl: false
    
  - platform: local_file
    name: "Last Captured Image"
    file_path: /config/www/last_capture.jpg

# Sensors for installation monitoring
sensor:
  - platform: template
    sensors:
      art_installation_status:
        friendly_name: "Art Installation Status"
        value_template: "{{ states('input_text.installation_status') }}"
        icon_template: >
          {% if is_state('input_text.installation_status', 'active') %}
            mdi:palette
          {% elif is_state('input_text.installation_status', 'error') %}
            mdi:alert-circle
          {% else %}
            mdi:sleep
          {% endif %}

# Input helpers
input_text:
  installation_status:
    name: "Installation Status"
    initial: "idle"
    max: 50

input_boolean:
  voice_interaction_active:
    name: "Voice Interaction Active"
    initial: false
    
  motion_detection_enabled:
    name: "Motion Detection Enabled"
    initial: true

input_number:
  interaction_timeout:
    name: "Interaction Timeout (seconds)"
    min: 10
    max: 300
    step: 10
    initial: 60

# RESTful sensors for Desiru app status
rest:
  - resource: "http://your-desiru-app.com:4567/health"
    method: GET
    name: "Desiru App Health"
    value_template: "{{ value_json.status }}"
    json_attributes:
      - timestamp
      - version
    scan_interval: 30

# Binary sensors for motion detection
binary_sensor:
  - platform: template
    sensors:
      visitor_present:
        friendly_name: "Visitor Present"
        value_template: >
          {{ is_state('binary_sensor.motion_sensor', 'on') or 
             is_state('input_boolean.voice_interaction_active', 'on') }}
        delay_off:
          minutes: 2

# Timers
timer:
  interaction_session:
    name: "Interaction Session Timer"
    duration: "00:01:00"
    restore: true

# Notifications
notify:
  - platform: file
    name: art_installation_log
    filename: /config/logs/art_installation.log
    timestamp: true
```

### secrets.yaml

```yaml
# secrets.yaml
latitude: 40.7128
longitude: -74.0060
elevation: 10
time_zone: "America/New_York"

# Desiru app configuration
desiru_app_url: "http://your-desiru-app.com:4567"
desiru_api_key: "your-api-key-here"

# Camera credentials
camera_username: "admin"
camera_password: "password123"
```

## Voice Assistant Integration

### Voice Conversation Handler

```yaml
# automations.yaml - Voice Interaction Automation
- id: voice_interaction_handler
  alias: "Voice Interaction Handler"
  description: "Handle voice interactions with Desiru art installation"
  trigger:
    - platform: event
      event_type: voice_assistant_speech_finished
      event_data:
        assistant_id: art_installation_assistant
  condition:
    - condition: state
      entity_id: rest.desiru_app_health
      state: "ok"
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

- id: voice_interaction_timeout
  alias: "Voice Interaction Timeout"
  description: "End voice interaction session after timeout"
  trigger:
    - platform: event
      event_type: timer.finished
      event_data:
        entity_id: timer.interaction_session
  action:
    - service: input_boolean.turn_off
      target:
        entity_id: input_boolean.voice_interaction_active
    - service: script.end_interaction_session
```

### Voice Processing Script

```yaml
# scripts.yaml
process_voice_input:
  alias: "Process Voice Input with Desiru"
  description: "Send voice input to Desiru app and handle response"
  fields:
    speech_text:
      description: "The transcribed speech text"
      example: "Create a beautiful sunset painting"
    session_id:
      description: "Unique session identifier"
      example: "session_123456"
  sequence:
    - service: notify.art_installation_log
      data:
        message: "Voice input received: {{ speech_text }}"
    
    # Send to Desiru app
    - service: rest_command.send_conversation_to_desiru
      data:
        message: "{{ speech_text }}"
        session_id: "{{ session_id }}"
        context:
          source: "voice_assistant"
          timestamp: "{{ now().isoformat() }}"
          location: "art_installation"
    
    # Wait for response and handle it
    - wait_template: "{{ states('sensor.desiru_last_response_id') != 'unknown' }}"
      timeout: "00:00:30"
      continue_on_timeout: true
    
    - choose:
        - conditions:
            - condition: template
              value_template: "{{ wait.completed }}"
        sequence:
          - service: script.handle_desiru_response
            data:
              response_data: "{{ state_attr('sensor.desiru_last_response', 'response_data') }}"
      default:
        - service: tts.google_say
          data:
            message: "I'm sorry, I'm having trouble processing your request right now. Please try again."
        - service: notify.art_installation_log
          data:
            message: "Timeout waiting for Desiru response"

handle_desiru_response:
  alias: "Handle Desiru Response"
  description: "Process response from Desiru app"
  fields:
    response_data:
      description: "Response data from Desiru app"
  sequence:
    - choose:
        # Text response - use TTS
        - conditions:
            - condition: template
              value_template: "{{ response_data.type == 'text' }}"
          sequence:
            - service: tts.google_say
              data:
                message: "{{ response_data.content }}"
                cache: false
        
        # Audio file response - play directly
        - conditions:
            - condition: template
              value_template: "{{ response_data.type == 'audio' }}"
          sequence:
            - service: media_player.play_media
              target:
                entity_id: media_player.art_installation_speaker
              data:
                media_content_id: "{{ response_data.audio_url }}"
                media_content_type: "audio/mpeg"
        
        # Image generation request
        - conditions:
            - condition: template
              value_template: "{{ response_data.type == 'image_request' }}"
          sequence:
            - service: script.capture_and_send_image
              data:
                request_id: "{{ response_data.request_id }}"
                camera_entity: "{{ response_data.camera | default('camera.installation_camera') }}"
        
        # Sensor query request
        - conditions:
            - condition: template
              value_template: "{{ response_data.type == 'sensor_query' }}"
          sequence:
            - service: script.query_and_send_sensor_data
              data:
                sensor_list: "{{ response_data.sensors }}"
                request_id: "{{ response_data.request_id }}"
        
        # Environmental control
        - conditions:
            - condition: template
              value_template: "{{ response_data.type == 'environment_control' }}"
          sequence:
            - service: script.control_environment
              data:
                commands: "{{ response_data.commands }}"
      
      default:
        - service: notify.art_installation_log
          data:
            message: "Unknown response type: {{ response_data.type }}"

end_interaction_session:
  alias: "End Interaction Session"
  description: "Clean up after interaction session ends"
  sequence:
    - service: rest_command.end_session_desiru
      data:
        session_id: "{{ states('sensor.current_session_id') }}"
    - service: input_text.set_value
      target:
        entity_id: input_text.installation_status
      data:
        value: "idle"
    - service: notify.art_installation_log
      data:
        message: "Interaction session ended"
```

## REST API Commands

### REST Commands Configuration

```yaml
# configuration.yaml - REST Commands
rest_command:
  send_conversation_to_desiru:
    url: "{{ desiru_app_url }}/api/v1/conversation"
    method: POST
    headers:
      Content-Type: "application/json"
      Authorization: "Bearer {{ desiru_api_key }}"
    payload: >
      {
        "message": "{{ message }}",
        "session_id": "{{ session_id }}",
        "context": {{ context | tojson }},
        "source": "home_assistant"
      }
    timeout: 30

  send_image_to_desiru:
    url: "{{ desiru_app_url }}/api/v1/upload_image"
    method: POST
    headers:
      Authorization: "Bearer {{ desiru_api_key }}"
    payload: "{{ image_data }}"
    content_type: "multipart/form-data"
    timeout: 60

  send_sensor_data_to_desiru:
    url: "{{ desiru_app_url }}/api/v1/sensor_data"
    method: POST
    headers:
      Content-Type: "application/json"
      Authorization: "Bearer {{ desiru_api_key }}"
    payload: >
      {
        "sensors": {{ sensor_data | tojson }},
        "timestamp": "{{ now().isoformat() }}",
        "location": "art_installation"
      }
    timeout: 15

  report_error_to_desiru:
    url: "{{ desiru_app_url }}/api/v1/error_report"
    method: POST
    headers:
      Content-Type: "application/json"
      Authorization: "Bearer {{ desiru_api_key }}"
    payload: >
      {
        "error_type": "{{ error_type }}",
        "error_message": "{{ error_message }}",
        "component": "{{ component }}",
        "timestamp": "{{ now().isoformat() }}",
        "severity": "{{ severity | default('medium') }}"
      }
    timeout: 10

  end_session_desiru:
    url: "{{ desiru_app_url }}/api/v1/session/end"
    method: POST
    headers:
      Content-Type: "application/json"
      Authorization: "Bearer {{ desiru_api_key }}"
    payload: >
      {
        "session_id": "{{ session_id }}",
        "timestamp": "{{ now().isoformat() }}"
      }
    timeout: 10
```

## Camera Integration

### Image Capture and Upload

```yaml
# scripts.yaml - Camera handling
capture_and_send_image:
  alias: "Capture and Send Image to Desiru"
  description: "Capture image from camera and send to Desiru app"
  fields:
    request_id:
      description: "Request ID from Desiru app"
    camera_entity:
      description: "Camera entity to capture from"
      default: "camera.installation_camera"
  sequence:
    - service: notify.art_installation_log
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
    
    # Send to Desiru app
    - service: shell_command.upload_image_to_desiru
      data:
        image_path: "/config/www/captures/capture_{{ request_id }}.jpg"
        request_id: "{{ request_id }}"
    
    # Clean up old captures (keep last 10)
    - service: shell_command.cleanup_old_captures

# Automatic image capture on motion
capture_on_motion:
  alias: "Capture Image on Motion Detection"
  description: "Automatically capture and send image when motion detected"
  sequence:
    - condition: state
      entity_id: input_boolean.motion_detection_enabled
      state: "on"
    
    - service: script.capture_and_send_image
      data:
        request_id: "motion_{{ now().timestamp() }}"
        camera_entity: "camera.installation_camera"
    
    - service: rest_command.send_motion_notification
      data:
        motion_type: "visitor_detected"
        confidence: "{{ state_attr('binary_sensor.motion_sensor', 'confidence') | default(0.8) }}"
        timestamp: "{{ now().isoformat() }}"
```

### Shell Commands for Image Handling

```yaml
# configuration.yaml - Shell Commands
shell_command:
  upload_image_to_desiru: >
    curl -X POST 
    -H "Authorization: Bearer {{ desiru_api_key }}" 
    -F "image=@{{ image_path }}" 
    -F "request_id={{ request_id }}" 
    -F "source=camera_capture" 
    "{{ desiru_app_url }}/api/v1/upload_image"

  cleanup_old_captures: >
    find /config/www/captures -name "*.jpg" -type f -mtime +1 -delete

  test_camera_connection: >
    curl -s -o /dev/null -w "%{http_code}" "http://192.168.1.100/snapshot"
```

## Sensor Integration

### Sensor Data Collection and Reporting

```yaml
# scripts.yaml - Sensor handling
query_and_send_sensor_data:
  alias: "Query and Send Sensor Data"
  description: "Collect sensor data and send to Desiru app"
  fields:
    sensor_list:
      description: "List of sensors to query"
    request_id:
      description: "Request ID from Desiru app"
  sequence:
    - variables:
        sensor_data: >
          {% set data = {} %}
          {% for sensor in sensor_list %}
            {% set sensor_state = states(sensor) %}
            {% set sensor_attrs = state_attr(sensor, 'all') %}
            {% set data = dict(data, **{sensor: {
              'state': sensor_state,
              'unit': state_attr(sensor, 'unit_of_measurement'),
              'friendly_name': state_attr(sensor, 'friendly_name'),
              'last_updated': state_attr(sensor, 'last_updated'),
              'attributes': sensor_attrs
            }}) %}
          {% endfor %}
          {{ data }}
    
    - service: rest_command.send_sensor_data_to_desiru
      data:
        sensor_data: "{{ sensor_data }}"
        request_id: "{{ request_id }}"
    
    - service: notify.art_installation_log
      data:
        message: "Sent sensor data for {{ sensor_list | length }} sensors"

# Periodic sensor reporting
report_all_sensors:
  alias: "Report All Installation Sensors"
  description: "Send comprehensive sensor report to Desiru app"
  sequence:
    - variables:
        all_sensors:
          - "sensor.temperature"
          - "sensor.humidity" 
          - "sensor.light_level"
          - "binary_sensor.motion_sensor"
          - "binary_sensor.door_sensor"
          - "sensor.sound_level"
          - "sensor.air_quality"
    
    - service: script.query_and_send_sensor_data
      data:
        sensor_list: "{{ all_sensors }}"
        request_id: "periodic_{{ now().timestamp() }}"
```

### Motion and Presence Detection

```yaml
# automations.yaml - Motion detection
- id: motion_detected_notification
  alias: "Motion Detected - Notify Desiru"
  description: "Send motion detection to Desiru app"
  trigger:
    - platform: state
      entity_id: binary_sensor.motion_sensor
      to: "on"
  condition:
    - condition: state
      entity_id: input_boolean.motion_detection_enabled
      state: "on"
  action:
    - service: rest_command.send_motion_notification
      data:
        motion_type: "motion_detected"
        sensor: "{{ trigger.entity_id }}"
        timestamp: "{{ trigger.to_state.last_updated }}"
        location: "main_gallery"
    
    - service: script.capture_on_motion
    
    - service: input_text.set_value
      target:
        entity_id: input_text.installation_status
      data:
        value: "visitor_detected"

- id: motion_cleared_notification  
  alias: "Motion Cleared - Notify Desiru"
  description: "Send motion cleared to Desiru app"
  trigger:
    - platform: state
      entity_id: binary_sensor.motion_sensor
      to: "off"
      for: "00:02:00"  # 2 minutes delay
  action:
    - service: rest_command.send_motion_notification
      data:
        motion_type: "motion_cleared"
        sensor: "{{ trigger.entity_id }}"
        timestamp: "{{ now().isoformat() }}"
        location: "main_gallery"
    
    - service: input_text.set_value
      target:
        entity_id: input_text.installation_status
      data:
        value: "idle"
```


## Error Handling and Reporting

### Error Detection Automations

```yaml
# automations.yaml - Error handling
- id: desiru_app_offline
  alias: "Desiru App Offline Error"
  description: "Handle when Desiru app becomes unavailable"
  trigger:
    - platform: state
      entity_id: rest.desiru_app_health
      to: "unavailable"
      for: "00:01:00"
  action:
    - service: script.handle_system_error
      data:
        error_type: "app_offline"
        error_message: "Desiru application is not responding"
        component: "desiru_app"
        severity: "high"
    
    - service: tts.google_say
      data:
        message: "I'm experiencing technical difficulties. Please try again in a few moments."
    
    - service: input_text.set_value
      target:
        entity_id: input_text.installation_status
      data:
        value: "error"

- id: camera_connection_error
  alias: "Camera Connection Error"
  description: "Handle camera connection failures"
  trigger:
    - platform: state
      entity_id: camera.installation_camera
      to: "unavailable"
      for: "00:00:30"
  action:
    - service: script.handle_system_error
      data:
        error_type: "camera_offline"
        error_message: "Installation camera is not responding"
        component: "camera.installation_camera"
        severity: "medium"
    
    - service: shell_command.test_camera_connection
    
    - delay: "00:00:05"
    
    - choose:
        - conditions:
            - condition: template
              value_template: "{{ states('sensor.camera_test_result') == '200' }}"
          sequence:
            - service: homeassistant.reload_config_entry
              target:
                entity_id: camera.installation_camera
      default:
        - service: notify.art_installation_log
          data:
            message: "Camera connection test failed - manual intervention required"

- id: voice_assistant_error
  alias: "Voice Assistant Error"
  description: "Handle voice assistant failures"
  trigger:
    - platform: event
      event_type: voice_assistant_error
  action:
    - service: script.handle_system_error
      data:
        error_type: "voice_assistant_error"
        error_message: "{{ trigger.event.data.error_message }}"
        component: "voice_assistant"
        severity: "medium"
    
    - service: voice_assistant.restart
      target:
        entity_id: voice_assistant.art_installation_assistant

- id: sensor_malfunction
  alias: "Sensor Malfunction Detection"
  description: "Detect and report sensor malfunctions"
  trigger:
    - platform: state
      entity_id: 
        - sensor.temperature
        - sensor.humidity
        - sensor.light_level
      to: "unavailable"
      for: "00:05:00"
  action:
    - service: script.handle_system_error
      data:
        error_type: "sensor_malfunction"
        error_message: "Sensor {{ trigger.entity_id }} is not responding"
        component: "{{ trigger.entity_id }}"
        severity: "low"
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
    - service: notify.art_installation_log
      data:
        message: "ERROR [{{ severity }}]: {{ error_type }} - {{ error_message }} ({{ component }})"
    
    # Report to Desiru app if it's available
    - condition: not
      conditions:
        - condition: state
          entity_id: rest.desiru_app_health
          state: "unavailable"
    
    - service: rest_command.report_error_to_desiru
      data:
        error_type: "{{ error_type }}"
        error_message: "{{ error_message }}"
        component: "{{ component }}"
        severity: "{{ severity }}"
    
    # Take corrective action based on severity
    - choose:
        - conditions:
            - condition: template
              value_template: "{{ severity == 'high' }}"
          sequence:
            - service: script.emergency_shutdown_procedure
        - conditions:
            - condition: template
              value_template: "{{ severity == 'medium' }}"
          sequence:
            - service: script.attempt_component_restart
              data:
                component: "{{ component }}"
      default:
        - service: script.log_minor_error
          data:
            error_details: "{{ error_type }}: {{ error_message }}"

emergency_shutdown_procedure:
  alias: "Emergency Shutdown Procedure"
  description: "Safe shutdown for critical errors"
  sequence:
    - service: tts.google_say
      data:
        message: "The art installation is temporarily unavailable due to technical issues. We apologize for the inconvenience."
    
    - service: input_boolean.turn_off
      target:
        entity_id: input_boolean.voice_interaction_active
    
    - service: input_boolean.turn_off
      target:
        entity_id: input_boolean.motion_detection_enabled
    
    - service: input_text.set_value
      target:
        entity_id: input_text.installation_status
      data:
        value: "emergency_shutdown"
    
    - service: notify.art_installation_log
      data:
        message: "EMERGENCY SHUTDOWN: Installation placed in safe mode"

attempt_component_restart:
  alias: "Attempt Component Restart"
  description: "Try to restart failed component"
  fields:
    component:
      description: "Component to restart"
  sequence:
    - choose:
        - conditions:
            - condition: template
              value_template: "{{ 'camera' in component }}"
          sequence:
            - service: homeassistant.reload_config_entry
              target:
                entity_id: "{{ component }}"
        - conditions:
            - condition: template
              value_template: "{{ 'voice_assistant' in component }}"
          sequence:
            - service: voice_assistant.restart
              target:
                entity_id: "{{ component }}"
        - conditions:
            - condition: template
              value_template: "{{ 'sensor' in component }}"
          sequence:
            - service: homeassistant.reload_config_entry
              target:
                entity_id: "{{ component }}"
      default:
        - service: notify.art_installation_log
          data:
            message: "No restart procedure defined for component: {{ component }}"
```

## Environmental Controls

### Lighting and Atmosphere Control

```yaml
# scripts.yaml - Environmental controls
control_environment:
  alias: "Control Installation Environment"
  description: "Adjust environmental settings based on Desiru app commands"
  fields:
    commands:
      description: "List of environmental control commands"
  sequence:
    - repeat:
        for_each: "{{ commands }}"
        sequence:
          - choose:
              # Lighting control
              - conditions:
                  - condition: template
                    value_template: "{{ repeat.item.type == 'lighting' }}"
                sequence:
                  - service: script.control_lighting
                    data:
                      action: "{{ repeat.item.action }}"
                      parameters: "{{ repeat.item.parameters }}"
              
              # Audio control
              - conditions:
                  - condition: template
                    value_template: "{{ repeat.item.type == 'audio' }}"
                sequence:
                  - service: script.control_audio
                    data:
                      action: "{{ repeat.item.action }}"
                      parameters: "{{ repeat.item.parameters }}"
              
              # Display control
              - conditions:
                  - condition: template
                    value_template: "{{ repeat.item.type == 'display' }}"
                sequence:
                  - service: script.control_display
                    data:
                      action: "{{ repeat.item.action }}"
                      parameters: "{{ repeat.item.parameters }}"
            
            default:
              - service: notify.art_installation_log
                data:
                  message: "Unknown environment control type: {{ repeat.item.type }}"

control_lighting:
  alias: "Control Installation Lighting"
  description: "Adjust lighting based on artistic requirements"
  fields:
    action:
      description: "Lighting action to perform"
    parameters:
      description: "Action parameters"
  sequence:
    - choose:
        # Set color
        - conditions:
            - condition: template
              value_template: "{{ action == 'set_color' }}"
          sequence:
            - service: light.turn_on
              target:
                entity_id: light.installation_lights
              data:
                rgb_color: "{{ parameters.rgb }}"
                brightness: "{{ parameters.brightness | default(255) }}"
                transition: "{{ parameters.transition | default(2) }}"
        
        # Set mood lighting
        - conditions:
            - condition: template
              value_template: "{{ action == 'set_mood' }}"
          sequence:
            - service: scene.turn_on
              target:
                entity_id: "scene.{{ parameters.mood }}_lighting"
        
        # Breathing effect
        - conditions:
            - condition: template
              value_template: "{{ action == 'breathing_effect' }}"
          sequence:
            - service: script.lighting_breathing_effect
              data:
                color: "{{ parameters.color }}"
                duration: "{{ parameters.duration | default(30) }}"
        
        # Turn off
        - conditions:
            - condition: template
              value_template: "{{ action == 'turn_off' }}"
          sequence:
            - service: light.turn_off
              target:
                entity_id: light.installation_lights
              data:
                transition: "{{ parameters.transition | default(5) }}"

control_audio:
  alias: "Control Installation Audio"
  description: "Manage audio output and ambient sounds"
  fields:
    action:
      description: "Audio action to perform"
    parameters:
      description: "Action parameters"
  sequence:
    - choose:
        # Play ambient sound
        - conditions:
            - condition: template
              value_template: "{{ action == 'play_ambient' }}"
          sequence:
            - service: media_player.play_media
              target:
                entity_id: media_player.installation_ambient
              data:
                media_content_id: "{{ parameters.sound_url }}"
                media_content_type: "audio/mpeg"
            - service: media_player.volume_set
              target:
                entity_id: media_player.installation_ambient
              data:
                volume_level: "{{ parameters.volume | default(0.3) }}"
        
        # Stop all audio
        - conditions:
            - condition: template
              value_template: "{{ action == 'stop_all' }}"
          sequence:
            - service: media_player.media_stop
              target:
                entity_id: 
                  - media_player.installation_ambient
                  - media_player.art_installation_speaker
        
        # Set volume
        - conditions:
            - condition: template
              value_template: "{{ action == 'set_volume' }}"
          sequence:
            - service: media_player.volume_set
              target:
                entity_id: "{{ parameters.player }}"
              data:
                volume_level: "{{ parameters.level }}"

control_display:
  alias: "Control Installation Display"
  description: "Manage visual displays and projections"
  fields:
    action:
      description: "Display action to perform"
    parameters:
      description: "Action parameters"
  sequence:
    - choose:
        # Show image
        - conditions:
            - condition: template
              value_template: "{{ action == 'show_image' }}"
          sequence:
            - service: shell_command.display_image
              data:
                image_url: "{{ parameters.image_url }}"
                duration: "{{ parameters.duration | default(10) }}"
        
        # Show text
        - conditions:
            - condition: template
              value_template: "{{ action == 'show_text' }}"
          sequence:
            - service: shell_command.display_text
              data:
                text: "{{ parameters.text }}"
                font_size: "{{ parameters.font_size | default(48) }}"
                color: "{{ parameters.color | default('#FFFFFF') }}"
        
        # Clear display
        - conditions:
            - condition: template
              value_template: "{{ action == 'clear' }}"
          sequence:
            - service: shell_command.clear_display
```

### Advanced Automation Scripts

```yaml
# scripts.yaml - Advanced automations
lighting_breathing_effect:
  alias: "Lighting Breathing Effect"
  description: "Create breathing light effect"
  fields:
    color:
      description: "RGB color for effect"
    duration:
      description: "Effect duration in seconds"
  sequence:
    - repeat:
        count: "{{ (duration | int / 4) | int }}"
        sequence:
          # Fade in
          - service: light.turn_on
            target:
              entity_id: light.installation_lights
            data:
              rgb_color: "{{ color }}"
              brightness: 255
              transition: 2
          - delay: "00:00:02"
          
          # Fade out
          - service: light.turn_on
            target:
              entity_id: light.installation_lights
            data:
              rgb_color: "{{ color }}"
              brightness: 50
              transition: 2
          - delay: "00:00:02"

adaptive_environment_response:
  alias: "Adaptive Environment Response"
  description: "Automatically adjust environment based on visitor presence and time"
  sequence:
    - variables:
        current_hour: "{{ now().hour }}"
        visitor_present: "{{ is_state('binary_sensor.visitor_present', 'on') }}"
        ambient_light: "{{ states('sensor.light_level') | int }}"
    
    - choose:
        # Daytime with visitors
        - conditions:
            - condition: template
              value_template: "{{ current_hour >= 9 and current_hour <= 17 and visitor_present }}"
          sequence:
            - service: scene.turn_on
              target:
                entity_id: scene.daytime_active
        
        # Evening with visitors
        - conditions:
            - condition: template
              value_template: "{{ current_hour >= 18 and current_hour <= 22 and visitor_present }}"
          sequence:
            - service: scene.turn_on
              target:
                entity_id: scene.evening_active
        
        # Night mode or no visitors
        - conditions:
            - condition: template
              value_template: "{{ current_hour >= 23 or current_hour <= 8 or not visitor_present }}"
          sequence:
            - service: scene.turn_on
              target:
                entity_id: scene.night_idle
      
      default:
        - service: scene.turn_on
          target:
            entity_id: scene.default_ambient

periodic_health_check:
  alias: "Periodic Health Check"
  description: "Regular system health monitoring"
  sequence:
    - service: script.query_and_send_sensor_data
      data:
        sensor_list:
          - "sensor.cpu_temperature"
          - "sensor.memory_usage"
          - "sensor.disk_usage"
          - "sensor.network_status"
        request_id: "health_check_{{ now().timestamp() }}"
    
    - service: shell_command.test_camera_connection
    
    - condition: template
      value_template: "{{ states('sensor.camera_test_result') != '200' }}"
    
    - service: script.handle_system_error
      data:
        error_type: "health_check_failure"
        error_message: "Camera connectivity test failed during health check"
        component: "camera.installation_camera"
        severity: "medium"
```

## Additional Shell Commands

```yaml
# configuration.yaml - Additional shell commands
shell_command:
  display_image: >
    curl -X POST 
    -H "Content-Type: application/json"
    -d '{"action": "display_image", "image_url": "{{ image_url }}", "duration": {{ duration }}}'
    "http://localhost:8080/display"

  display_text: >
    curl -X POST 
    -H "Content-Type: application/json"
    -d '{"action": "display_text", "text": "{{ text }}", "font_size": {{ font_size }}, "color": "{{ color }}"}'
    "http://localhost:8080/display"

  clear_display: >
    curl -X POST 
    -H "Content-Type: application/json"
    -d '{"action": "clear"}'
    "http://localhost:8080/display"

  get_system_stats: >
    curl -s "http://localhost:8080/stats" | jq -r '.cpu_usage'
```

## Periodic Automations

```yaml
# automations.yaml - Periodic tasks
- id: periodic_sensor_report
  alias: "Periodic Sensor Report"
  description: "Send sensor data to Desiru app every 5 minutes"
  trigger:
    - platform: time_pattern
      minutes: "/5"
  condition:
    - condition: state
      entity_id: rest.desiru_app_health
      state: "ok"
  action:
    - service: script.report_all_sensors

- id: periodic_health_check
  alias: "Periodic Health Check"
  description: "Perform system health check every 15 minutes"
  trigger:
    - platform: time_pattern
      minutes: "/15"
  action:
    - service: script.periodic_health_check

- id: adaptive_environment_update
  alias: "Adaptive Environment Update"
  description: "Update environment based on conditions every hour"
  trigger:
    - platform: time_pattern
      minutes: 0
  action:
    - service: script.adaptive_environment_response

- id: daily_log_rotation
  alias: "Daily Log Rotation"
  description: "Rotate logs daily at midnight"
  trigger:
    - platform: time
      at: "00:00:00"
  action:
    - service: shell_command.rotate_logs
    - service: notify.art_installation_log
      data:
        message: "Daily log rotation completed"
```

This comprehensive Home Assistant integration provides a complete voice-controlled interface for your Desiru interactive art installation, handling voice interactions, camera capture, sensor monitoring, error reporting, and environmental controls through REST API communications.

