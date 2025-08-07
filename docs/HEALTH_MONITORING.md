# Health Monitoring Architecture

## Overview

The Glitch Cube uses a dual-path health monitoring system that ensures redundancy and flexibility:
1. **Home Assistant** pushes health status directly to Uptime Kuma
2. **Sinatra** provides health endpoints for monitoring and optional push capability

## Components

### 1. Home Assistant Health Aggregation

#### Health Monitoring Sensor (`sensor.health_monitoring`)
Location: `config/homeassistant/template/health_monitoring.yaml`

Consolidates all system metrics into a compact string:
```
WiFi:XXdBm | Up:XXd | HA:IP | API:status | CPU:XX°C | Mem:XX% | Disk:XX%
```

Includes attributes:
- Network status (WiFi strength, IPs)
- Service health (HA, Sinatra API)
- System metrics (CPU temp, memory, disk)
- Activity data (last interaction, deployment, persona)

### 2. Sinatra Health Endpoints

#### GET /health
Returns Sinatra application health with circuit breaker status:
```json
{
  "status": "healthy",
  "circuit_breakers": {
    "home_assistant": {
      "state": "closed",
      "failure_count": 0
    },
    "openrouter": {
      "state": "closed",
      "failure_count": 0
    }
  }
}
```

#### GET /health/push
Optional endpoint that:
1. Reads `sensor.health_monitoring` from Home Assistant
2. If `UPTIME_KUMA_PUSH_URL` is configured, pushes to Uptime Kuma
3. Returns the health data and push status

Service: `Services::HealthPushService`

### 3. REST Sensor Monitoring

#### Glitch Cube API Health (`sensor.glitchcube_api_health`)
Location: `config/homeassistant/sensors/rest_glitchcube_api_health.yaml`

- Polls Sinatra `/health` endpoint every 30 seconds
- States: `healthy`, `degraded`, `unknown`
- Includes circuit breaker attributes

## Monitoring Flows

### Primary Flow: Home Assistant → Uptime Kuma
```
System Metrics → sensor.health_monitoring → HA Automation → Uptime Kuma
                                          ↓
                              (Every 55s or on state change)
```

Configuration:
- Automation: `config/homeassistant/automations/update_external_status_page.yaml`
- REST Command: `config/homeassistant/rest_commands.yaml`
- Uptime Kuma URL: Hardcoded in REST command

### Secondary Flow: Sinatra → Uptime Kuma (Optional)
```
External Monitor → GET /health/push → Reads HA sensor → Pushes to Uptime Kuma
```

Configuration:
- Environment Variable: `UPTIME_KUMA_PUSH_URL`
- Service: `lib/services/health_push_service.rb`

### Health Check Flow: HA → Sinatra
```
sensor.glitchcube_api_health → GET /health → Circuit Breaker Status
         ↓ (every 30s)
    Updates HA sensor
```

## Uptime Kuma Configuration

### Home Assistant Direct Push
- **URL**: `https://status.wlux.casa/api/push/Bf8nrx6ykq`
- **Method**: GET with query parameters
- **Parameters**:
  - `status`: up/down based on health
  - `msg`: Health monitoring sensor state
  - `ping`: Simulated based on WiFi strength

### Sinatra Optional Push
- **URL**: Set via `UPTIME_KUMA_PUSH_URL` environment variable
- **Method**: GET with query parameters
- **Usage**: Only if explicitly configured

## Webhook Communications

### Sinatra → Home Assistant Updates
Service: `Services::HomeAssistantWebhookService`

Send status updates to Home Assistant:
```ruby
webhook = Services::HomeAssistantWebhookService.new
webhook.record_interaction(source: 'api')
webhook.update_persona('BUDDY')
webhook.update_environment('Burning Man')
```

Updates Home Assistant entities:
- `input_text.current_environment`
- `input_text.current_weather`
- `input_number.avg_sound_db`
- `input_text.current_persona`
- `input_datetime.last_interaction`

## Failure Scenarios

### Circuit Breaker States
When external services fail, circuit breakers protect the system:
- **Closed**: Normal operation
- **Open**: Service failing, fallback mode active
- **Half-Open**: Testing recovery

### Degraded Mode
When circuit breakers are open:
- Health endpoint returns `status: "degraded"`
- Uptime Kuma still receives "up" status (system is responding)
- Home Assistant continues local operations

### Complete Failure
If Sinatra is completely down:
- REST sensor shows `unknown`
- Home Assistant automation marks status as `down`
- Uptime Kuma receives failure notification

## Testing Health Monitoring

### Test Sinatra Health
```bash
curl http://localhost:4567/health
```

### Test Health Push
```bash
curl http://localhost:4567/health/push
```

### Test Home Assistant Webhook
```bash
curl -X POST http://homeassistant.local:8123/api/webhook/glitchcube_update \
  -H "Content-Type: application/json" \
  -d '{"persona":"BUDDY","interaction":true}'
```

### Verify REST Sensor
In Home Assistant Developer Tools:
- Check state of `sensor.glitchcube_api_health`
- Check state of `sensor.health_monitoring`

## Configuration Reference

### Environment Variables
```bash
# Optional - only if Sinatra should push to Uptime Kuma
UPTIME_KUMA_PUSH_URL=https://status.example.com/api/push/YOUR_PUSH_ID
```

### Key Files
- **Home Assistant**:
  - `config/homeassistant/template/health_monitoring.yaml` - Health aggregation
  - `config/homeassistant/sensors/rest_glitchcube_api_health.yaml` - API monitoring
  - `config/homeassistant/automations/update_external_status_page.yaml` - Push automation
  - `config/homeassistant/rest_commands.yaml` - REST command definitions

- **Sinatra**:
  - `lib/services/health_push_service.rb` - Health push service
  - `lib/services/home_assistant_webhook_service.rb` - HA webhook client
  - `app.rb` - Health endpoints

## Benefits of Dual-Path Approach

1. **Redundancy**: If one path fails, the other continues
2. **Flexibility**: Can monitor from either system
3. **Simplicity**: Each component has clear responsibilities
4. **Debugging**: Multiple observation points for troubleshooting
5. **Independence**: Systems can operate autonomously