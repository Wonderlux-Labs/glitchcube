# Camera Vision Analysis Setup

## Overview
This setup integrates LLM vision analysis with Home Assistant camera and motion sensors to automatically analyze and describe what's happening in the camera feed when motion is detected.

## Components Created

### 1. Automations (`config/homeassistant/automations/camera_vision_analysis.yaml`)
- **camera_motion_vision_analysis**: Triggers when motion is detected
  - Calls LLM vision analyzer
  - Stores result in input_text helper
  - Sends notification for interesting events
  - Has 60-second cooldown to prevent excessive API calls
  
- **clear_camera_vision_analysis**: Clears analysis after 5 minutes of no motion

### 2. Input Text Helper (`config/homeassistant/input_helpers/input_text.yaml`)
- **camera_vision_analysis**: Stores the latest camera analysis (max 255 chars)

### 3. Template Sensors (`config/homeassistant/template/camera_vision_sensor.yaml`)
- **sensor.camera_vision_status**: Status indicator (idle/people_detected/activity_detected)
- **sensor.camera_people_count**: Extracted people count from analysis

### 4. Scripts (`config/homeassistant/scripts/analyze_camera.yaml`)
- **analyze_camera_now**: Manual trigger for immediate analysis
- **analyze_camera_with_prompt**: Custom prompt analysis with configurable duration

## Configuration Required

### Update Entity IDs
You need to update the following entity IDs to match your actual setup:

1. In `camera_vision_analysis.yaml`:
   - Replace `binary_sensor.camera_motion` with your actual motion sensor
   - Replace `camera.camera` with your actual camera entity

2. In template sensors:
   - Update `binary_sensor.camera_motion` reference if needed

### LLM Vision Provider
The current configuration uses provider ID `01K21T5563YK72553SX49G9WK3`. Update this if you're using a different provider.

## Usage

### Automatic Operation
Once configured, the system will:
1. Detect motion via your motion sensor
2. Automatically analyze the camera feed for 5 seconds
3. Store the analysis in `input_text.camera_vision_analysis`
4. Update template sensors with extracted information
5. Send notifications for interesting events

### Manual Operation
You can manually trigger analysis:
```yaml
# From Developer Tools > Services
service: script.analyze_camera_now

# Or with custom prompt
service: script.analyze_camera_with_prompt
data:
  prompt: "Count the number of people and describe their activities"
  duration: 10
```

### Access Analysis Data
The analysis is available through:
- **State**: `states('input_text.camera_vision_analysis')`
- **Sensor**: `states('sensor.camera_vision_status')`
- **People Count**: `states('sensor.camera_people_count')`

### Integration with Glitch Cube
The camera analysis can be accessed in your Ruby application:
```ruby
# Get the current camera analysis
analysis = home_assistant_client.get_state('input_text.camera_vision_analysis')
people_count = home_assistant_client.get_state('sensor.camera_people_count')

# Trigger manual analysis
home_assistant_client.call_service('script', 'analyze_camera_now')
```

## Troubleshooting

### No Analysis Triggered
- Check motion sensor is working: `states('binary_sensor.camera_motion')`
- Verify camera entity exists: `states('camera.camera')`
- Check automation is enabled in Home Assistant UI

### Analysis Fails
- Verify LLM Vision integration is installed and configured
- Check provider ID is correct
- Review Home Assistant logs for errors

### Rate Limiting
The automation has a 60-second cooldown. Adjust this in the condition:
```yaml
{{ last_triggered is none or (now() - last_triggered).total_seconds() > 60 }}
```

## Performance Considerations
- Each analysis uses 4 frames over 5 seconds
- Images are resized to 1280px width to reduce API costs
- Maximum 100 tokens per response to minimize usage
- Consider adjusting cooldown period based on your needs

## Future Enhancements
- Store historical analyses in database
- Track patterns over time
- Integrate with conversation module for contextual awareness
- Add face recognition for known individuals
- Implement zone-based motion detection