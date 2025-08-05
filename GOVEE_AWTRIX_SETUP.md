# Govee MQTT & AWTRIX Matrix Clock Setup Guide

## Overview
This guide sets up both Govee lighting control via MQTT and AWTRIX matrix clock integration for the Glitch Cube art installation. These integrations provide:

- **Govee Lights**: Dynamic lighting that responds to conversation mood, battery level, and visitor presence
- **AWTRIX Clock**: Matrix display showing conversation status, environmental data, battery level, and interactive prompts

## Quick Start

### 1. Deploy Govee2MQTT Bridge
```bash
# Deploy with Govee integration
docker-compose -f docker-compose.yml -f docker-compose.govee.yml up -d
```

### 2. Configure Environment Variables
Add to your `.env` file:
```bash
# MQTT Configuration
MQTT_USERNAME=glitchcube
MQTT_PASSWORD=glitchcube123

# Govee API (optional but recommended)
GOVEE_API_KEY=your-govee-api-key
GOVEE_EMAIL=your-govee-email@example.com
GOVEE_PASSWORD=your-govee-password
```

### 3. Install AWTRIX HACS Integration
1. Open HACS in Home Assistant
2. Go to Integrations
3. Add custom repository: `https://github.com/10der/homeassistant-custom_components-awtrix`
4. Install "AWTRIX" integration
5. Restart Home Assistant

## Detailed Setup

### Govee Device Setup

#### Hardware Requirements
- Govee H6xxx, H7xxx, or H8xxx series lights
- Wi-Fi connectivity
- Optional: Govee API key for cloud features

#### Enable LAN API
1. Open Govee Home app
2. Go to device settings
3. Enable "LAN Control" if available
4. Note device IP addresses

#### Govee2MQTT Features
- **LAN API**: Direct local control (fastest, works offline)
- **IoT API**: Real-time status updates via AWS IoT
- **Platform API**: Fallback via Govee cloud service

### AWTRIX Clock Setup

#### Hardware Requirements
- Ulanzi TC001 Smart Pixel Clock (recommended)
- Or custom ESP32-based matrix display
- Wi-Fi connectivity

#### Flash AWTRIX3 Firmware
1. Visit: https://blueforcer.github.io/awtrix3/#/flasher
2. Connect device via USB
3. Click "Install AWTRIX3"
4. Configure Wi-Fi (AP password: `12345678`)

#### Configure in Home Assistant
Add to `configuration.yaml`:
```yaml
awtrix:
  - host: 192.168.1.XXX  # Your AWTRIX device IP
    name: glitchcube_display
    scan_interval: 30
```

## Smart Automations Created

### Lighting Automations
- **Visitor Detection**: Welcome lighting when motion detected
- **Conversation Moods**: Colors change based on AI personality
- **Battery Warnings**: Orange/red lights for low battery
- **Night Mode**: Automatic dimming after sunset
- **Charging Status**: Green breathing effect when charging

### Display Automations
- **Conversation Status**: Shows active visitors and chat state
- **Battery Monitoring**: Hourly updates and critical alerts
- **Environmental Data**: Temperature/humidity every 15 minutes
- **Weather Info**: Morning weather display
- **Special Events**: Holiday and event notifications
- **Error Alerts**: System health warnings
- **Daily Stats**: Evening summary of interactions

## Integration Features

### Govee Light Scenes
- **Curious**: Blue breathing effect
- **Excited**: Orange strobe lighting  
- **Contemplative**: Purple fade effect
- **Battery Critical**: Red strobe warning
- **Visitor Welcome**: Green pulse greeting
- **Night Mode**: Dim blue ambient

### AWTRIX Display Apps
- **Conversation Status**: Visitor count + chat state
- **Battery Level**: Percentage with color coding
- **Environmental**: Temperature and humidity
- **Weather**: Current conditions with icons
- **Messages**: Custom installation notifications
- **Prompts**: Interactive visitor encouragements

## Testing the Setup

### Test Govee Lights
```yaml
# Home Assistant Service Call
service: script.conversation_mood_lighting
data:
  mood: "excited"
  intensity: 80
```

### Test AWTRIX Display
```yaml
# Home Assistant Service Call
service: script.show_installation_message
data:
  message: "Hello World!"
  icon_id: "52176"
  duration: 15
  color: "[255, 255, 255]"
```

### Verify MQTT Integration
```bash
# Check Govee2MQTT logs
docker logs govee2mqtt

# Test MQTT topics
mosquitto_pub -h localhost -t "govee/test" -m "hello"
```

## Icon Resources

### AWTRIX Icons
- **LaMetric Database**: https://developer.lametric.com/icons
- **Built-in Icons**: Access via AWTRIX web interface
- **Common IDs**:
  - Robot: `52176`
  - Battery: `15710` (full), `15711` (medium), `15712` (low)
  - Temperature: `2282`
  - Microphone: `18586`
  - Warning: `23035`

### Govee Scene Colors
- **RGB Values**: Use `{"r": 255, "g": 100, "b": 0}` format
- **Effects**: `solid`, `breathing`, `strobe`, `fade`, `pulse`
- **Brightness**: 0-100 scale

## Troubleshooting

### Govee Issues
- **No Discovery**: Check LAN API enabled in Govee app
- **Connection Failed**: Verify device IP addresses
- **Slow Response**: Try API key for cloud fallback

### AWTRIX Issues
- **Display Not Found**: Check device IP and Wi-Fi connection
- **Apps Not Showing**: Verify HACS integration installed
- **Icons Missing**: Use LaMetric icon IDs or upload custom

### MQTT Issues
- **Connection Failed**: Check mosquitto container health
- **No Messages**: Verify MQTT credentials in `.env`
- **Discovery Not Working**: Restart Home Assistant after config changes

## Advanced Configuration

### Custom Govee Scenes
Add new scenes to `scripts/govee_scenes.yaml`:
```yaml
my_custom_scene:
  alias: "My Custom Scene"
  sequence:
    - service: mqtt.publish
      data:
        topic: "govee/{{ govee_device_id }}/set"
        payload: '{"brightness": 100, "color": {"r": 255, "g": 0, "b": 255}}'
```

### Custom AWTRIX Apps
Add new displays to `scripts/awtrix_displays.yaml`:
```yaml
show_custom_data:
  alias: "Show Custom Data"
  sequence:
    - service: awtrix.glitchcube_display_push_app_data
      data:
        name: "custom"
        data:
          text: "{{ states('sensor.my_sensor') }}"
          icon: "12345"
          color: [255, 255, 255]
```

## Maintenance

### Regular Tasks
- Monitor govee2mqtt container logs
- Check AWTRIX device connectivity
- Update HACS integrations monthly
- Verify MQTT broker health

### Backup Important Files
- `config/homeassistant/mqtt.yaml`
- `config/homeassistant/scripts/`
- `config/homeassistant/automations/`
- `docker-compose.govee.yml`

The setup is now complete and ready for plug-and-play operation!