# Hardware Integration Guide

## Overview
The Glitch Cube integrates with various hardware systems through Home Assistant, providing a unified interface for all physical interactions.

## AWTRIX LED Display

### Overview
32x8 RGB LED matrix display for visual feedback and information display.

### Integration
- Controlled via Home Assistant scripts
- Service: `script.awtrix_send_custom_app`
- Tools: `display_tool.rb`, `lighting_tool.rb`

### Key Functions
- Text display with scrolling
- Mood lighting (RGB colors)
- Custom apps and animations
- Notification display

### Configuration
```yaml
# Home Assistant script example
script:
  awtrix_display_text:
    sequence:
      - service: mqtt.publish
        data:
          topic: awtrix_prefix/custom/glitch_message
          payload_template: >
            {
              "text": "{{ text }}",
              "color": "{{ color | default('#FFFFFF') }}",
              "duration": {{ duration | default(10) }}
            }
```

## GPS Tracking

### Hardware
- Traccar-compatible GPS device
- Real-time position updates via cellular
- Battery-powered with solar charging

### Integration Points
- Location sensor: `sensor.glitchcube_location`
- GPS coordinates: `sensor.cube_tracker_latitude/longitude`
- Battery level: `sensor.cube_tracker_battery`

### Usage
```ruby
# Get current location in Ruby
client = HomeAssistantClient.new
location = client.state('sensor.glitchcube_location')
```

## Audio System

### Text-to-Speech
- Multiple voice options via Home Assistant
- Character-specific voices (Buddy, Jax, Lomi, Zorp)
- Service: `tts.cloud_say` or `tts.speak`

### Media Players
- `media_player.everywhere`: All speakers
- `media_player.square_voice`: Primary cube speaker
- Volume control and media playback

## LED Feedback System

### States
- `listening`: Blue pulsing
- `thinking`: Yellow spinning
- `speaking`: Green wave
- `completed`: White fade
- `error`: Red flash

### Control via Tools
```ruby
# Via conversation_feedback tool
execute_tool_call('conversation_feedback', 'set_state', { state: 'thinking' })
```

## Starlink Connectivity

### Network Configuration
- Primary WAN: Starlink satellite internet
- Backup: Cellular hotspot failover
- Local network: WiFi for all devices

### Bandwidth Management
- QoS for voice interactions (highest priority)
- API calls second priority
- Background tasks lowest priority

## Power System

### Components
- 24-hour battery bank
- Solar charging panels
- Automatic transfer switch
- UPS for critical systems

### Monitoring
- Battery level: `sensor.battery_percentage`
- Solar input: `sensor.solar_watts`
- Power consumption: `sensor.power_draw_watts`

## Environmental Sensors

### Available Sensors
- Temperature: `sensor.cube_temperature`
- Humidity: `sensor.cube_humidity`
- Motion: `binary_sensor.cube_motion`
- Sound level: `sensor.cube_sound_level`

### Usage in Conversations
```ruby
# Enrich context with sensor data
context = enrich_context_with_sensors(context)
```

## Testing Hardware

### Console Commands
```ruby
# Test TTS
test_speak("Hello world", :buddy)

# Test display
ha.awtrix_display_text("Testing", color: [255, 0, 0])

# Test mood light
ha.awtrix_mood_light([0, 255, 0], brightness: 80)

# Get all states
ha.states
```

### Direct Home Assistant Testing
```bash
# SSH to Home Assistant VM
ssh root@glitch.local

# Test service calls
ha-cli service call script.awtrix_display_text --arguments text="Test"
```

## Troubleshooting

### Common Issues

1. **AWTRIX not responding**
   - Check MQTT connection
   - Verify power to display
   - Check Home Assistant logs

2. **TTS not working**
   - Verify media player is online
   - Check volume levels
   - Test with different TTS service

3. **GPS not updating**
   - Check cellular connection
   - Verify Traccar server status
   - Check device battery

## Related Documentation
- [Home Assistant Integration](./home_assistant_integration.md)
- [Conversation System](./conversation-system.md)
- [Tool System](../TOOL_SYSTEM.md)