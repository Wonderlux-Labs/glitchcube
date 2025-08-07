#!/bin/bash

# Script to push health status to Uptime Kuma
# Can be called by cron or external monitoring
# Falls back to direct push if Sinatra is down

SINATRA_URL="${SINATRA_URL:-http://localhost:4567}"
UPTIME_KUMA_URL="${UPTIME_KUMA_PUSH_URL:-https://status.wlux.casa/api/push/Bf8nrx6ykq}"
TIMEOUT=5

echo "[$(date)] Checking health and pushing to Uptime Kuma..."

# Try to get health from Sinatra's /health/push endpoint
# This will try HA first, then fall back to local health
response=$(curl -s -m $TIMEOUT "$SINATRA_URL/health/push" 2>/dev/null)
curl_exit=$?

if [ $curl_exit -eq 0 ] && [ -n "$response" ]; then
    # Sinatra responded - it should have pushed to Uptime Kuma if configured
    echo "✅ Sinatra health push succeeded"
    echo "Response: $response"
else
    # Sinatra is down - push directly to Uptime Kuma
    echo "⚠️ Sinatra not responding, pushing directly to Uptime Kuma"
    
    # Generate a minimal health message
    message="HA:UNKNOWN | API:DOWN | Recovery:ATTEMPTING"
    
    # Push directly to Uptime Kuma
    direct_response=$(curl -s -m $TIMEOUT "$UPTIME_KUMA_URL?status=down&msg=$message&ping=0" 2>/dev/null)
    direct_exit=$?
    
    if [ $direct_exit -eq 0 ]; then
        echo "✅ Direct push to Uptime Kuma succeeded"
    else
        echo "❌ Failed to push to Uptime Kuma"
        exit 1
    fi
fi

echo "[$(date)] Health push complete"