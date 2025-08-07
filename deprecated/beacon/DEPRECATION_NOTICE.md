# Beacon Service Deprecation

**Deprecated:** January 2025  
**Replacement:** Health Push Service with Uptime Kuma integration

## Overview

The Beacon Service was originally designed to send comprehensive telemetry data to an external monitoring endpoint. It has been deprecated in favor of a simpler health push mechanism that integrates with Uptime Kuma.

## Files Deprecated

- `lib/jobs/beacon_heartbeat_job.rb` - Background job for periodic heartbeats
- `lib/services/beacon_service.rb` - Service for sending telemetry data
- `scripts/test_beacon.rb` - Test script for beacon functionality

## Replacement

The new health monitoring approach uses:

1. **Home Assistant sensor.health_monitoring** - Consolidates all health metrics
2. **HealthPushService** (`lib/services/health_push_service.rb`) - Reads HA sensor and pushes to Uptime Kuma
3. **GET /health/push endpoint** - Simple endpoint that can be called by Uptime Kuma or other monitors

## Migration

To migrate from beacon to the new system:

1. Configure `sensor.health_monitoring` in Home Assistant with all needed metrics
2. Set `UPTIME_KUMA_PUSH_URL` environment variable (optional)
3. Use the `/health/push` endpoint for monitoring

## Rationale

The beacon service was over-engineered for the actual monitoring needs:
- If the system is up, health data can be queried directly via existing endpoints
- If the system is down, it can't send telemetry anyway
- Uptime Kuma provides sufficient external monitoring
- The simplified approach reduces complexity and maintenance burden