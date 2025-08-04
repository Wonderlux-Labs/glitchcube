#!/bin/bash
# Health check script for Glitch Cube installation

set -e

echo "🎲 Glitch Cube Health Check"
echo "=========================="
echo ""

# Function to check service health
check_service() {
    local service=$1
    local url=$2
    local expected=$3
    
    echo -n "Checking $service... "
    
    if curl -sf "$url" > /dev/null; then
        echo "✅ OK"
        return 0
    else
        echo "❌ FAILED"
        return 1
    fi
}

# Check Docker services
echo "📊 Docker Services Status:"
docker-compose ps
echo ""

# Check API endpoints
echo "🔍 API Health Checks:"
check_service "Glitch Cube API" "http://localhost:4567/health"
check_service "Home Assistant" "http://localhost:8123/api/"
echo ""

# Check Redis
echo -n "Checking Redis... "
if docker exec glitchcube_redis redis-cli ping > /dev/null 2>&1; then
    echo "✅ OK"
else
    echo "❌ FAILED"
fi
echo ""

# Check resource usage
echo "💾 Resource Usage:"
docker stats --no-stream
echo ""

# Check disk space
echo "💿 Disk Space:"
df -h | grep -E "^/dev/|Filesystem"
echo ""

# Check temperature (Pi-specific for desert conditions)
echo "🌡️  System Temperature:"
if command -v vcgencmd >/dev/null 2>&1; then
  temp=$(vcgencmd measure_temp 2>/dev/null | cut -d'=' -f2 || echo "unknown")
  echo "CPU Temperature: $temp"
  
  # Warning if over 70°C (critical for desert deployment)
  if [[ "$temp" =~ ^[0-9]+\.[0-9]+\'C$ ]]; then
    temp_num=$(echo "$temp" | cut -d"'" -f1)
    if (( $(echo "$temp_num > 70" | bc -l) 2>/dev/null )); then
      echo "🚨 WARNING: High temperature detected ($temp) - Monitor for throttling!"
    fi
  fi
else
  echo "Temperature monitoring not available (non-Pi system)"
fi
echo ""

# Check network connectivity (important for Starlink)
echo "🌐 Network Status:"
if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
  echo "✅ Internet connectivity - OK"
else
  echo "❌ Internet connectivity - FAILED (Check Starlink connection)"
fi
echo ""

# Check recent logs for errors
echo "📋 Recent Errors (last 10 minutes):"
echo "Glitch Cube App:"
docker-compose logs --since 10m glitchcube 2>&1 | grep -iE "error|exception|failed" | tail -5 || echo "No recent errors"
echo ""

echo "Sidekiq:"
docker-compose logs --since 10m sidekiq 2>&1 | grep -iE "error|exception|failed" | tail -5 || echo "No recent errors"
echo ""

# Check if mock mode is enabled
if docker exec glitchcube_app printenv MOCK_HOME_ASSISTANT 2>/dev/null | grep -q "true"; then
    echo "⚠️  Note: Mock Home Assistant mode is enabled"
fi

# Summary
echo "=========================="
echo "Health check complete!"
echo ""
echo "Quick commands:"
echo "- View logs: docker-compose logs -f"
echo "- Restart all: docker-compose restart"
echo "- Stop all: docker-compose down"
echo "- Update: git pull && docker-compose build && docker-compose up -d"