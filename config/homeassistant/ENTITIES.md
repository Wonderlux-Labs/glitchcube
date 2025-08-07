# Home Assistant Entity Reference

## Motion Detection Entities

### Primary Motion Sensor
- **Entity ID**: `input_boolean.motion_detected`
- **Type**: Input Boolean (switch)
- **Location**: `/config/homeassistant/input_helpers/input_boolean.yaml`
- **Description**: Main motion detection sensor for the Glitch Cube
- **Used By**:
  - Camera vision analysis automation
  - Sensor update webhook
  - Reset all sensors script

### ⚠️ Fixed Entity References
Previously incorrect references have been corrected:
- ~~`switch.motion_detected`~~ → `input_boolean.motion_detected`
- ~~`binary_sensor.camera_motion`~~ → `input_boolean.motion_detected`

## Human Detection Entities

### Human Detected
- **Entity ID**: `input_boolean.human_detected`
- **Type**: Input Boolean
- **Description**: Indicates if a human has been detected

## Movement & Position Entities

### Cube Movement
- `input_boolean.cube_is_moving` - Cube is currently moving
- `input_boolean.cube_stopped_moving` - Cube just stopped moving
- `input_boolean.cube_tilted` - Cube is tilted
- `input_boolean.cube_stable` - Cube is stable (default: true)

## System Health Entities

### Health Monitoring
- `sensor.health_monitoring` - Compact health status string for Uptime Kuma
  - Format: `WiFi:XXdBm | Up:XXd | HA:IP | API:status | CPU:XX°C | Mem:XX% | Disk:XX%`
- `sensor.health_monitoring_compact` - Ultra-compact status for SMS/notifications
  - Format: `W:wifi A:api T:temp M:mem%`
- `sensor.health_monitoring_json` - Full JSON status with all metrics
  - Contains: network, services, system, and activity data

### Battery & Resources
- `input_boolean.battery_low` - Battery level is low
- `input_boolean.resources_low` - System resources are low
- `input_boolean.temp_critical` - Temperature is critical

## Camera Entities

### Camera Stream
- **Entity ID**: `camera.camera`
- **Type**: Camera
- **Description**: Main camera feed for vision analysis

### Vision Analysis Storage
- **Entity ID**: `input_text.camera_vision_analysis`
- **Type**: Input Text
- **Description**: Stores the latest LLM vision analysis result

### Vision Status Sensor
- **Entity ID**: `sensor.camera_vision_status`
- **Type**: Template Sensor
- **States**: `idle`, `people_detected`, `activity_detected`
- **Attributes**:
  - `analysis_text` - The full analysis text
  - `last_analysis` - Timestamp of last analysis
  - `people_detected` - Boolean if people detected
  - `motion_active` - Current motion state

### People Count
- **Entity ID**: `sensor.camera_people_count`
- **Type**: Template Sensor
- **Description**: Estimated number of people from vision analysis

## Updating Sensors via API

### Webhook Endpoint
`POST /api/v1/sensor_data`

Example payload:
```json
{
  "motion_detected": true,
  "human_detected": false,
  "cube_is_moving": false,
  "battery_level": 85,
  "temperature": 22.5
}
```

The webhook automatically updates the corresponding input_boolean entities.

## Scripts

### Reset All Sensors
- **Entity ID**: `script.reset_all_sensors`
- **Description**: Resets all motion/detection sensors to false
- **Resets**:
  - `input_boolean.motion_detected`
  - `input_boolean.human_detected`
  - `input_boolean.cube_is_moving`
  - `input_boolean.cube_stopped_moving`
  - `input_boolean.cube_tilted`

## Automations

### Camera Motion Vision Analysis
- **Trigger**: `input_boolean.motion_detected` turns on
- **Action**: Analyzes camera feed with LLM vision
- **Stores**: Result in `input_text.camera_vision_analysis`

### Clear Camera Vision Analysis
- **Trigger**: `input_boolean.motion_detected` off for 5 minutes
- **Action**: Clears the vision analysis text

### Update Sensors from Webhook
- **Trigger**: Webhook received at `/api/v1/sensor_data`
- **Action**: Updates all sensor states based on payload