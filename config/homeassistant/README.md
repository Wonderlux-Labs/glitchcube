# Glitch Cube Home Assistant Configuration

This directory contains the Home Assistant configuration files for the Glitch Cube art installation.

## File Overview

### Core Configuration
- `configuration.yaml` - Main HA configuration with basic settings, integrations, and includes
- `sensors.yaml` - Health monitoring sensors and template sensors for installation state
- `automations.yaml` - Webhook handlers and automated responses
- `scripts.yaml` - Reusable scripts for testing and maintenance
- `scenes.yaml` - Different operational modes for the installation

## Key Features

### Health Monitoring Sensors
- **Glitch Cube App Health** - Monitors Sinatra app via REST endpoint
- **Internet Connectivity** - Tests external internet access (important for Starlink)
- **CPU Temperature** - Uses Glances sensor `cube_cpu_thermal_0_temperature` (Fahrenheit)
- **System Uptime** - Uses Glances sensor `cube_uptime` for system uptime tracking
- **Installation Health** - Composite sensor summarizing overall system status

### Dynamic State Sensors
- **Last Interaction Time** - Tracks when users last interacted with the installation
- **Current Persona** - Tracks which AI personality is currently active
- **Current Environment** - Text description of current location and conditions
- **Offline Mode** - Binary sensor indicating if installation is operating without internet
- **Installation Health** - Overall health status (healthy/warning/degraded/offline/critical)

### Physical Interaction Sensors
- **Motion Detected** - PIR/movement sensor for people approaching
- **Human Detected** - Advanced detection for human presence (face detection, etc.)

### Cube Movement & Position Sensors
- **Cube Is Moving** - Accelerometer detection for transport/movement
- **Cube Stopped Moving** - End of movement detection
- **Cube Tilted** - Gyroscope detection for rotation/tilting
- **Cube Stable** - Settled and ready for interaction

### System Health Binary Sensors
- **Battery Low** - Power level warning
- **Resources Low** - CPU/memory/storage warnings
- **Temperature Critical** - Extreme temperature alert (beyond normal monitoring)

### Environmental Sensors
- **Average Sound Level** - Numeric sensor (0-120 dB) for ambient noise monitoring

### Webhook Endpoints

All webhooks are accessible at `http://glitchcube.local:8123/api/webhook/{webhook_id}`

#### Update Last Interaction
- **Endpoint**: `/api/webhook/glitchcube_interaction`
- **Method**: POST
- **Payload**: `{"source": "conversation"}` (optional)
- **Action**: Updates the last interaction timestamp

#### Update Current Persona
- **Endpoint**: `/api/webhook/glitchcube_persona` 
- **Method**: POST
- **Payload**: `{"persona": "Mysterious Guide"}`
- **Action**: Changes the current AI persona

#### Text-to-Speech
- **Endpoint**: `/api/webhook/glitchcube_speak`
- **Method**: POST
- **Payload**: 
  ```json
  {
    "message": "Welcome to the Glitch Cube",
    "media_player": "media_player.glitchcube_speaker",
    "language": "en",
    "voice": "default"
  }
  ```
- **Action**: Speaks the message through the configured audio system

#### Update Environment Description
- **Endpoint**: `/api/webhook/glitchcube_environment`
- **Method**: POST
- **Payload**: `{"environment": "We are in the city, it is hot and sunny, not too loud, at a coffee bar"}`
- **Action**: Updates the current environment description

#### Update Sound Level
- **Endpoint**: `/api/webhook/glitchcube_sound`
- **Method**: POST
- **Payload**: `{"sound_db": 65.5}`
- **Action**: Updates the average sound level in decibels

#### Update Binary Sensors
- **Endpoint**: `/api/webhook/glitchcube_sensors`
- **Method**: POST
- **Payload**: 
  ```json
  {
    "motion_detected": true,
    "human_detected": false,
    "cube_is_moving": false,
    "cube_stable": true,
    "cube_tilted": false,
    "battery_low": false,
    "resources_low": false,
    "temp_critical": false
  }
  ```
- **Action**: Updates any combination of binary sensors (only include sensors you want to change)

### Scripts Available

- `test_health_sensors` - Forces update of all health sensors for testing
- `simulate_interaction` - Simulates a user interaction for testing
- `change_persona` - Changes AI persona with logging
- `speak_with_persona` - TTS with persona-appropriate voice selection
- `emergency_shutdown` - Emergency shutdown sequence
- `generate_health_report` - Comprehensive health report for beacon service
- `toggle_offline_mode` - Manually toggle offline mode for testing or emergency
- `simulate_motion` - Simulates motion detection (5 second pulse)
- `simulate_human_interaction` - Simulates full human interaction sequence
- `simulate_cube_movement` - Simulates cube transport sequence (moving → stopped → stable)
- `test_all_sensors` - Reports current status of all sensors
- `reset_all_sensors` - Resets all sensors to their default state

### Scenes for Different Modes

- **Installation Active** - Normal operation mode
- **Maintenance Mode** - For system maintenance
- **Sleep Mode** - Low power/overnight mode  
- **Demo Mode** - For demonstrations and showcasing
- **Alert Mode** - Emergency/problem alert state

## Integration with Glitch Cube App

The Sinatra application should make HTTP requests to the webhook endpoints to:

1. **Record Interactions**: POST to `glitchcube_interaction` after each user conversation
2. **Update Persona**: POST to `glitchcube_persona` when switching AI personalities
3. **Speak Responses**: POST to `glitchcube_speak` for TTS output

## Testing

Use the provided scripts to test functionality:

```yaml
# Test all health sensors
service: script.test_health_sensors

# Simulate user interaction
service: script.simulate_interaction

# Change persona
service: script.change_persona
data:
  persona_name: "Mysterious Guide"

# Speak a message
service: script.speak_with_persona
data:
  message: "Hello from the Glitch Cube"
  media_player: "media_player.glitchcube_speaker"
```

## Hardware Integration Notes

- Temperature monitoring uses Glances integration (`sensor.cube_cpu_thermal_0_temperature`)
- System uptime tracking via Glances (`sensor.cube_uptime`) 
- Media player configuration will need to match your actual audio hardware
- Light controls are commented out until RGB hardware is connected
- Adjust sensor scan intervals based on performance needs

## Desert Installation Considerations

- Temperature alerts set for 158°F (70°C equivalent, suitable for hot desert conditions)
- Internet monitoring accounts for Starlink connectivity issues
- Health monitoring designed for 24/7 autonomous operation
- Uptime tracking for maintenance scheduling and reliability metrics
- Logging configured for remote diagnostics via beacon service