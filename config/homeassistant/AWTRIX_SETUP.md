# AWTRIX Matrix Clock Setup for Glitch Cube

## Overview
This setup configures AWTRIX3 matrix clock integration with Home Assistant for the Glitch Cube art installation.

## Hardware Requirements
- Ulanzi TC001 Smart Pixel Clock (or compatible AWTRIX3 device)
- ESP32-based matrix display
- Wi-Fi connectivity

## Step 1: Flash AWTRIX3 Firmware

1. **Connect Device**: Plug Ulanzi TC001 into computer via USB-C
2. **Flash Firmware**: Visit https://blueforcer.github.io/awtrix3/#/flasher
3. **Select Device**: Choose your ESP32 device in the web flasher
4. **Install Firmware**: Click "Install AWTRIX3" and wait for completion
5. **Power On**: Turn on device by pressing left + right arrow buttons simultaneously

## Step 2: Configure Device Wi-Fi

1. **Access Point Mode**: Device creates "AWTRIX3_XXXXXX" network
2. **Connect**: Use password `12345678` to connect
3. **Configure**: Open browser to `192.168.4.1` and set up Wi-Fi
4. **Find IP**: Note the device IP address once connected

## Step 3: Install HACS Custom Component

1. **Add Repository**: In HACS, add custom repository:
   ```
   https://github.com/10der/homeassistant-custom_components-awtrix
   ```

2. **Install Integration**: Install "AWTRIX" integration from HACS

3. **Restart Home Assistant**: Required after installation

## Step 4: Configure Integration

Add to `configuration.yaml`:

```yaml
awtrix:
  - host: 192.168.1.XXX  # Your AWTRIX device IP
    name: glitchcube_display
    scan_interval: 30
```

## Step 5: Test Integration

Basic notification test:
```yaml
service: notify.awtrix_glitchcube_display
data:
  message: "Glitch Cube Online!"
  data:
    icon: "52176"  # Robot icon
    sound: beep
    duration: 10
```

## Available Services

### notify.awtrix_*
Send notifications to display

### awtrix.*_push_app_data
Create custom apps with:
- Text display
- Icons
- Animations
- Duration control

### awtrix.*_settings
Modify display settings:
- Brightness
- Time format
- Transitions
- Colors

### awtrix.*_weather_app
Display weather information with custom icons

## Icon Resources

- **LaMetric Icons**: https://developer.lametric.com/icons
- **Built-in Icons**: Available through AWTRIX web interface
- **Custom Icons**: Upload via AWTRIX API

## Integration with Glitch Cube

The display will show:
- Conversation status
- Visitor count
- Battery level
- Environmental data
- Art installation notifications
- Interactive prompts