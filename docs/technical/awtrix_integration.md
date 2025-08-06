# AWTRIX 3 Integration

This document describes the AWTRIX 3 clock display integration with GlitchCube.

## Overview

The AWTRIX 3 is a smart pixel clock that can display custom messages, notifications, and mood lighting. GlitchCube integrates with AWTRIX via MQTT through Home Assistant.

## Configuration

### Prerequisites

1. AWTRIX 3 device connected to your network
2. MQTT broker running (configured in Home Assistant)
3. AWTRIX configured to connect to the MQTT broker

### MQTT Topics

The integration uses the following MQTT topics:
- Custom apps: `awtrix/custom/[app_name]`
- Notifications: `awtrix/notify`
- Mood light: `awtrix/moodlight`

## Usage

### Ruby API (HomeAssistantClient)

```ruby
# Initialize the client
ha_client = HomeAssistantClient.new

# Display text on AWTRIX
ha_client.awtrix_display_text("Hello World!")

# Display with custom parameters
ha_client.awtrix_display_text(
  "Rainbow Text",
  app_name: 'myapp',
  color: [255, 0, 0],    # Red text
  duration: 10,          # Show for 10 seconds
  rainbow: true,         # Rainbow effect
  icon: '1234'          # Icon ID
)

# Send a notification (stays until dismissed)
ha_client.awtrix_notify(
  "Alert!",
  color: [255, 0, 0],    # Red text
  hold: true,            # Keep until dismissed
  sound: 'alarm',        # Play alarm sound
  icon: '5678'          # Icon ID
)

# Clear the display
ha_client.awtrix_clear_display

# Set mood lighting
ha_client.awtrix_mood_light(
  [255, 0, 255],        # Purple color
  brightness: 50        # 50% brightness
)
```

### Home Assistant Scripts

The integration includes Home Assistant scripts that can be called directly:

#### Display Custom App
```yaml
service: script.awtrix_send_custom_app
data:
  app_name: "glitchcube"
  text: "Hello World"
  color: [255, 255, 255]
  duration: 5
  rainbow: false
  icon: "1234"  # Optional
```

#### Send Notification
```yaml
service: script.awtrix_send_notification
data:
  text: "Alert!"
  color: [255, 0, 0]
  hold: true
  wakeup: true
  sound: "alarm"  # Optional
  icon: "5678"    # Optional
```

#### Clear Display
```yaml
service: script.awtrix_clear_display
```

#### Set Mood Light
```yaml
service: script.awtrix_set_mood_light
data:
  color: [255, 0, 255]
  brightness: 100
```

## Parameters

### Text Display Parameters
- `text` (string): The text to display
- `app_name` (string): Name of the custom app (no spaces)
- `color` (array): RGB color values [R, G, B]
- `duration` (integer): Display duration in seconds
- `rainbow` (boolean): Enable rainbow text effect
- `icon` (string): Icon ID or base64 encoded 8x8 image

### Notification Parameters
- `text` (string): Notification text
- `color` (array): RGB color values [R, G, B]
- `hold` (boolean): Keep notification until dismissed
- `wakeup` (boolean): Turn on matrix if off
- `sound` (string): Sound to play (RTTTL or MP3 filename)
- `icon` (string): Icon ID or base64 encoded 8x8 image

### Mood Light Parameters
- `color` (array): RGB color values [R, G, B]
- `brightness` (integer): Brightness level (0-255)

## Error Handling

All methods include error handling and will return `false` if the operation fails, logging a warning message. The application will continue to function even if AWTRIX is unavailable.

## Testing

Run the AWTRIX integration tests:
```bash
bundle exec rspec spec/lib/home_assistant_client_awtrix_spec.rb
```

## Example Use Cases

### Display Conversation Status
```ruby
# Show when GlitchCube is thinking
ha_client.awtrix_display_text(
  "Thinking...",
  color: [0, 255, 255],  # Cyan
  rainbow: true,
  duration: 30
)

# Show when ready for interaction
ha_client.awtrix_display_text(
  "Ready!",
  color: [0, 255, 0],    # Green
  duration: 5
)
```

### Battery Alerts
```ruby
# Low battery warning
if battery_level < 20
  ha_client.awtrix_notify(
    "Low Battery: #{battery_level}%",
    color: [255, 0, 0],    # Red
    hold: true,
    sound: 'alarm'
  )
end
```

### Mood Indication
```ruby
# Set mood light based on conversation sentiment
case mood
when 'happy'
  ha_client.awtrix_mood_light([255, 255, 0], brightness: 150)  # Yellow
when 'sad'
  ha_client.awtrix_mood_light([0, 0, 255], brightness: 50)     # Blue
when 'excited'
  ha_client.awtrix_mood_light([255, 0, 255], brightness: 200)  # Magenta
end
```

## Troubleshooting

### Common Issues

1. **Messages not appearing**: Check MQTT broker connectivity
2. **Colors incorrect**: Ensure RGB values are in [0-255] range
3. **Sound not playing**: Verify sound file exists on AWTRIX device

### Debug MQTT

Test MQTT directly:
```bash
# Subscribe to AWTRIX topics
mosquitto_sub -h localhost -t "awtrix/#" -v

# Send test message
mosquitto_pub -h localhost -t "awtrix/custom/test" \
  -m '{"text":"Test","color":[255,0,0]}'
```