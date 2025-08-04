#!/bin/bash
# Simple service restart script for gallery staff

set -e

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "🔄 Restarting Glitch Cube Services"
echo "=================================="

if [[ ! -f "$APP_DIR/docker-compose.yml" ]]; then
    echo "❌ Error: docker-compose.yml not found"
    exit 1
fi

echo "Restarting all services..."
docker-compose -f docker-compose.yml -f docker-compose.production.yml restart

echo ""
echo "✅ All services restarted"
echo ""
echo "📊 Current status:"
docker-compose -f docker-compose.yml -f docker-compose.production.yml ps

echo ""
echo "💡 To check system health: ./scripts/status-check.sh"