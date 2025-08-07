# Home Assistant ↔ Sinatra Integration Map

## Overview
This document maps all integration points between Home Assistant and the Glitch Cube Sinatra application.

## Health Monitoring Flow

### 1. Sinatra Health Endpoints
- **GET /health** - Returns circuit breaker status (`healthy` or `degraded`)
- **GET /health/push** - Reads HA's `sensor.health_monitoring` and optionally pushes to Uptime Kuma

### 2. Home Assistant → Sinatra Monitoring
- **sensor.glitchcube_api_health** - REST sensor polling `/health` every 30s
  - Returns: `healthy`, `degraded`, or `unknown`
  - Located: `sensors/rest_glitchcube_api_health.yaml`

### 3. Health Data Aggregation
- **sensor.health_monitoring** - Template sensor consolidating all metrics
  - Combines: WiFi, uptime, IPs, API status, CPU temp, memory, disk
  - Format: Compact string for Uptime Kuma message field
  - Located: `template/health_monitoring.yaml`

### 4. Uptime Kuma Push Flow
```
HA sensor.health_monitoring → Sinatra /health/push → Uptime Kuma
                           ↓
           HA automation also pushes directly to Uptime Kuma
```

## Webhook Communications

### Sinatra → Home Assistant
- **Webhook URL**: `http://homeassistant.local:8123/api/webhook/glitchcube_update`
- **Service**: `Services::HomeAssistantWebhookService` 
- **Webhook ID**: `glitchcube_update`
- **Automation**: `automations/webhook_updates.yaml`
- **Updates**:
  - `input_text.current_environment` - Environment name
  - `input_text.current_weather` - Weather status
  - `input_number.avg_sound_db` - Sound level
  - `input_text.current_persona` - Active persona
  - `input_datetime.last_interaction` - Last interaction timestamp

### Home Assistant → Sinatra (Voice Conversations)
- **Endpoint**: `POST /api/v1/ha_webhook`
- **Purpose**: Home Assistant voice assistant integration
- **Event Types**: `conversation_started`, `conversation_ended`

## REST Commands (HA → Sinatra)

### Status Updates
- **update_status_page** - Direct push to Uptime Kuma
  - URL: Hardcoded Uptime Kuma push URL
  - Triggered: Every 55 seconds or on state changes
  - Automation: `automations/update_external_status_page.yaml`

### Deployment
- **trigger_glitchcube_deployment** - Trigger deployment via Sinatra
- **check_deployment_status** - Check deployment status
- **manual_glitchcube_deployment** - Manual deployment trigger
- Located: `rest_commands.yaml`

## Key Sensors & Helpers

### Input Helpers (State Storage)
- `input_text.glitchcube_host_ip` - Sinatra host IP
- `input_text.glitchcube_host_url` - Sinatra base URL
- `input_text.current_persona` - Active persona
- `input_text.current_environment` - Environment name
- `input_datetime.last_interaction` - Last interaction time
- `input_boolean.offline_mode` - Offline mode flag

### System Sensors (Referenced in health_monitoring)
- `sensor.wifi_signal_strength` - WiFi signal in dBm
- `sensor.uptime` - System uptime
- `sensor.processor_temperature` - CPU temperature
- `sensor.memory_use_percent` - Memory usage
- `sensor.disk_use_percent` - Disk usage
- `binary_sensor.internet_connectivity` - Internet connection status
- `binary_sensor.remote_ui` - Home Assistant remote UI status

## Configuration Files

### Core Configuration
- `configuration.yaml` - Main HA configuration
- `automations.yaml` - Main automations file
- `rest_commands.yaml` - REST command definitions

### Modular Configurations
- `automations/*.yaml` - Individual automation files
- `sensors/*.yaml` - REST and other sensors
- `template/*.yaml` - Template sensors
- `input_helpers/*.yaml` - Input helpers

## Integration Issues Found & Fixed

### 1. ✅ REST Sensor Naming
- **Issue**: REST sensor named `glitch_cube_app_health` but templates expect `glitchcube_api_health`
- **Fix**: Created new `rest_glitchcube_api_health.yaml` with correct naming

### 2. ✅ Health Endpoint Response
- **Issue**: REST sensor expected `status: "ok"` but Sinatra returns `status: "healthy"`
- **Fix**: Updated value_template to use actual response values

### 3. ✅ Beacon Service Deprecated
- **Old**: Complex beacon service sending telemetry
- **New**: Simple health push using HA's consolidated sensor

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

## Monitoring Chain Summary

1. **Sinatra** exposes `/health` endpoint
2. **HA REST sensor** polls health every 30s → `sensor.glitchcube_api_health`
3. **HA template sensor** aggregates all metrics → `sensor.health_monitoring`
4. **HA automation** pushes to Uptime Kuma every 55s
5. **Sinatra** `/health/push` can read HA sensor and push to Uptime Kuma
6. **Uptime Kuma** receives push updates with consolidated health string