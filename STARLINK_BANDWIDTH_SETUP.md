# Starlink Bandwidth Monitoring for Burning Man

## Overview
Comprehensive bandwidth monitoring for Glitch Cube at Burning Man with a strict 50GB weekly Starlink data limit. Uses Starlink's native gRPC API for accurate real-time usage tracking.

## 🎯 Key Features

### Smart Monitoring
- **Direct gRPC API**: Polls Starlink dish every 10 minutes for accurate throughput data
- **Real-time Usage**: Live bandwidth consumption with MB/minute calculations
- **Weekly Tracking**: Automatic weekly usage totals (50GB limit)
- **Daily Averages**: 7.14GB/day target tracking

### Automatic Conservation
- **80% Warning**: Orange lights + AWTRIX alert at 40GB used
- **95% Critical**: Red strobe + conservation mode at 47.5GB used
- **AI Throttling**: Automatically reduces model complexity and response frequency
- **Connection Monitoring**: Offline mode when Starlink disconnects

### Visual Alerts
- **AWTRIX Display**: Usage percentages, warnings, and daily summaries
- **Govee Lighting**: Color-coded usage status (green→orange→red)
- **Home Assistant**: Comprehensive dashboard with charts and metrics

## 📊 Monitoring Dashboard

### Key Sensors Created
- `sensor.burning_man_weekly_usage_gb` - Current week usage
- `sensor.burning_man_weekly_usage_percent` - Usage percentage (0-100%)
- `sensor.burning_man_remaining_data` - Remaining GB this week
- `sensor.starlink_total_throughput_mbps` - Current bandwidth usage
- `sensor.estimated_days_remaining` - How long data will last

### Visual Indicators
- **Green (0-60%)**: Normal usage, full AI functionality
- **Orange (60-80%)**: Moderate usage, first warning
- **Red (80-95%)**: High usage, conservation suggestions  
- **Critical Red (95%+)**: Conservation mode automatically enabled

## 🚨 Automatic Responses

### At 80% Usage (40GB)
- Orange warning lights
- AWTRIX display: "80% Data Used!"
- Email/log alerts
- Suggestion to enable conservation mode

### At 95% Usage (47.5GB)
- Red strobe emergency lights
- AWTRIX display: "CRITICAL: 95% Data Used!"
- **Auto-enable conservation mode**:
  - Switch to smaller AI model (gemini-2.0-flash-thinking)
  - Increase response delay to 30 seconds
  - Reduce conversation frequency

### Conservation Mode Features
- Smaller, more efficient AI models
- Longer delays between AI responses
- Reduced background sync operations
- Priority to essential installation functions
- Auto-restore when usage drops below 85%

## 🛠️ Technical Implementation

### Starlink gRPC Integration
```yaml
# REST sensor polling Starlink every 10 minutes
- platform: rest
  name: "Starlink Status"
  resource: "http://192.168.100.1:9000/api/v1/starlink/status"
  scan_interval: 600  # 10 minutes
```

### Alternative Command Line Method
```yaml
# Using grpcurl command for direct gRPC calls
- platform: command_line
  name: "Starlink gRPC Data"
  command: >
    grpcurl -plaintext -d '{}' 192.168.100.1:9200 
    SpaceX.API.Device.Device/Handle
```

### Data Accumulation
```yaml
utility_meter:
  starlink_weekly_usage:
    source: sensor.starlink_data_usage_bytes
    cycle: weekly
    name: "Starlink Weekly Data Usage"
```

## 📋 Setup Instructions

### 1. Prerequisites
Ensure Starlink is accessible at `192.168.100.1:9200` (standard gRPC endpoint)

### 2. Install grpcurl (Optional)
```bash
# Ubuntu/Debian
sudo apt-get install grpcurl

# macOS
brew install grpcurl

# Manual install
wget https://github.com/fullstorydev/grpcurl/releases/download/v1.8.7/grpcurl_1.8.7_linux_x86_64.tar.gz
```

### 3. Test Starlink Connection
```bash
./scripts/starlink_grpc_check.sh
```

### 4. Enable in Home Assistant
All sensors and automations are automatically loaded from:
- `config/homeassistant/sensors/starlink_bandwidth.yaml`
- `config/homeassistant/automations/starlink_bandwidth.yaml`

### 5. Configure Input Helpers
The system creates:
- `input_boolean.bandwidth_conservation_mode`
- `input_boolean.offline_mode`
- `input_number.ai_response_delay`
- `input_text.current_ai_model`

## 📈 Usage Calculations

### Bandwidth Math
- **50GB/week** = 7.14GB/day average
- **Text-only LLM calls**: ~1-10KB per request
- **10,000 conversations/day**: Still only ~100MB
- **Main usage**: System updates, logs, image uploads

### Conservation Triggers
- **Daily > 7.14GB**: Evening warning
- **Weekly > 40GB (80%)**: Orange alert + conservation suggestion
- **Weekly > 47.5GB (95%)**: Critical mode + automatic throttling

### Estimation Logic
```yaml
estimated_days_remaining:
  value_template: >
    {% set remaining_gb = states('sensor.burning_man_remaining_data') | float(0) %}
    {% set daily_avg = states('sensor.burning_man_daily_usage_gb') | float(0.1) %}
    {{ (remaining_gb / daily_avg) | round(1) }}
```

## 🔧 Troubleshooting

### Connection Issues
- Verify Starlink router at 192.168.100.1
- Check gRPC port 9200 accessibility
- Test with manual grpcurl command

### Missing Data
- REST sensor timeout (increase from 30s)
- gRPC service restart required
- Network routing to Starlink dish

### Conservation Mode Stuck
- Manually disable: `input_boolean.bandwidth_conservation_mode`
- Check weekly usage percentage sensor
- Verify automation conditions

## 🎨 Integration with Art Installation

### AWTRIX Display Messages
- **Hourly**: Current usage percentage
- **Daily (9 PM)**: Usage summary  
- **Warnings**: Immediate bandwidth alerts
- **Conservation**: Status when throttling active

### Govee Lighting Integration
- **Normal**: Standard conversation mood lighting
- **Warning**: Orange breathing effect
- **Critical**: Red strobe emergency pattern
- **Conservation**: Dim blue conservation mode

### Conversation Impact
- **Normal Mode**: Full AI personality and responsiveness
- **Conservation Mode**: 
  - Longer pauses between responses
  - Shorter AI-generated messages
  - Priority to essential interactions
  - Reduced background processing

## 📊 Monitoring Tools

### Glances Network View
- Real-time network interface usage
- System-level bandwidth monitoring
- Container resource consumption

### Home Assistant Dashboard
- Weekly usage charts
- Daily consumption trends
- Signal quality metrics
- Connection status history

### Log Analysis
All bandwidth events logged to:
- Home Assistant logbook
- System logs with structured data
- Conservation mode state changes

The system is designed for completely autonomous operation during Burning Man, automatically managing the 50GB limit while maintaining the art installation's core interactive experience.