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