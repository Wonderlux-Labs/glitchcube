# Uptime Kuma Monitoring Architecture

## Overview

Glitch Cube uses a **resilient multi-path monitoring system** that ensures Uptime Kuma always receives health updates, even during partial system failures.

## Monitoring Paths (Priority Order)

### 1. Primary Path: Home Assistant → Uptime Kuma
**When**: Normal operation, all systems healthy
```
System Metrics → sensor.health_monitoring → HA Automation → Uptime Kuma
                                          ↓
                          (Every 55s or on state change)
```
- **URL**: `https://status.wlux.casa/api/push/Bf8nrx6ykq` (hardcoded in HA)
- **Status**: Always "up" if HA can push
- **Message**: Full system metrics (WiFi, CPU, Memory, Disk, etc.)

### 2. Secondary Path: Sinatra → Uptime Kuma (with HA data)
**When**: External monitor calls Sinatra, HA is up
```
External Monitor → GET /health/push → Read HA sensor → Push to Uptime Kuma
```
- **URL**: Same as primary (via `UPTIME_KUMA_PUSH_URL` env var)
- **Status**: "up" if both Sinatra and HA healthy
- **Message**: HA's sensor.health_monitoring data

### 3. Fallback Path: Sinatra → Uptime Kuma (without HA)
**When**: HA is down but Sinatra is running
```
External Monitor → GET /health/push → Generate local health → Push to Uptime Kuma
```
- **URL**: Same as primary (via `UPTIME_KUMA_PUSH_URL` env var)
- **Status**: "up" if Sinatra healthy (even with HA down)
- **Message**: "HA:DOWN | API:OK | Up:XXh | Issues:..."

### 4. Emergency Path: Direct Push
**When**: Both HA and Sinatra are down
```
Monitoring Script → Direct HTTP call → Uptime Kuma
```
- **URL**: Hardcoded in script
- **Status**: "down"
- **Message**: "HA:UNKNOWN | API:DOWN | Recovery:ATTEMPTING"

## Configuration

### Environment Variables
```bash
# In .env or .env.production
UPTIME_KUMA_PUSH_URL=https://status.wlux.casa/api/push/Bf8nrx6ykq
```

### Home Assistant
```yaml
# config/homeassistant/rest_commands.yaml
update_status_page:
  url: "https://status.wlux.casa/api/push/Bf8nrx6ykq?status={{ status }}&msg={{ msg | urlencode }}&ping={{ ping }}"
```

### Uptime Kuma Setup
1. Create a "Push" monitor in Uptime Kuma
2. Set heartbeat interval to 60 seconds
3. Configure the monitoring script as HTTP(s) Keyword monitor:
   - URL: `http://speedygonzo.local:4567/health/push`
   - Keyword: "pushed"
   - Interval: 60 seconds

## Health Message Format

### Normal Operation (HA Available)
```
WiFi:-52dBm | Up:3d | HA:192.168.1.100 | API:healthy | CPU:45°C | Mem:42% | Disk:68%
```

### Degraded Operation (HA Down)
```
HA:DOWN | API:OK | Up:3.5h | Issues:home_assistant:open
```

### Critical Failure
```
HA:UNKNOWN | API:DOWN | Recovery:ATTEMPTING
```

## Monitoring Script

The `scripts/push_health_to_uptime_kuma.sh` script provides belt-and-suspenders monitoring:

1. First tries Sinatra's `/health/push` endpoint
2. If Sinatra is down, pushes directly to Uptime Kuma
3. Can be run via cron for guaranteed regular updates

### Cron Setup (Optional)
```bash
# Add to crontab for every minute monitoring
* * * * * /Users/eristmini/glitch/glitchcube/scripts/push_health_to_uptime_kuma.sh >> /tmp/health_push.log 2>&1
```

## Recovery Scenarios

### Scenario 1: Home Assistant Crashes
1. HA automation stops pushing
2. Uptime Kuma HTTP monitor hits `/health/push`
3. Sinatra detects HA is down
4. Pushes "HA:DOWN | API:OK" message
5. Status remains "up" (Sinatra is working)

### Scenario 2: Sinatra Crashes
1. HA continues pushing via automation
2. Status remains "up" with full metrics
3. Uptime Kuma HTTP monitor fails (optional second monitor)

### Scenario 3: Both Crash
1. No automatic pushes
2. Monitoring script detects failures
3. Pushes "API:DOWN" directly to Uptime Kuma
4. Status becomes "down"
5. Triggers alerts for manual intervention

### Scenario 4: Network Issues
1. Local services running but can't reach internet
2. All push attempts fail
3. Uptime Kuma marks as down after 60 seconds
4. Recovery scripts can run locally

## Testing

### Test Primary Path (HA)
```bash
# Trigger HA automation manually
curl -X POST http://glitch.local:8123/api/services/automation/trigger \
  -H "Authorization: Bearer YOUR_HA_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"entity_id": "automation.update_external_status_page"}'
```

### Test Secondary Path (Sinatra with HA)
```bash
# Call Sinatra health push endpoint
curl http://localhost:4567/health/push
```

### Test Fallback Path (Sinatra without HA)
```bash
# Stop HA, then call Sinatra
docker-compose stop homeassistant
curl http://localhost:4567/health/push
```

### Test Emergency Path (Direct)
```bash
# Run monitoring script
./scripts/push_health_to_uptime_kuma.sh
```

## Key Benefits

1. **No Single Point of Failure**: Multiple paths ensure monitoring continues
2. **Graceful Degradation**: System reports what it can, when it can
3. **Clear Status Messages**: Easy to identify what's wrong from the message
4. **Automatic Recovery Detection**: When services come back, monitoring resumes
5. **External Visibility**: Even when on-site systems fail, remote monitoring continues