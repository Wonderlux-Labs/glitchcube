#!/bin/bash
# Update script for Glitch Cube on Raspberry Pi
# Run with: bash update-raspi.sh

set -e

echo "🎲 Glitch Cube Update Script"
echo "=========================="

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Error: docker-compose.yml not found. Run this script from the project root."
    exit 1
fi

# Show current version if git is available
if command -v git &> /dev/null; then
    echo "📊 Current version:"
    git log -1 --oneline
    echo ""
fi

# Pull latest changes
echo "📥 Pulling latest changes..."
git pull

# Pull latest base images
echo "🐳 Pulling latest Docker images..."
docker-compose pull

# Build the application image
echo "🔨 Building application image..."
docker-compose build

# Stop services gracefully
echo "🛑 Stopping services..."
docker-compose -f docker-compose.yml -f docker-compose.production.yml down

# Start services with new images
echo "🚀 Starting updated services..."
docker-compose -f docker-compose.yml -f docker-compose.production.yml up -d

# Wait for services to be healthy
echo "⏳ Waiting for services to be healthy..."
sleep 15

# Check service status
echo "📊 Service status:"
docker-compose ps

# Clean up old images to save space
echo "🧹 Cleaning up old images..."
docker image prune -f

# Show disk usage
echo ""
echo "💾 Disk usage:"
df -h | grep -E "Filesystem|/$"

echo ""
echo "✅ Update complete!"
echo ""
echo "View logs: docker-compose -f docker-compose.yml -f docker-compose.production.yml logs -f"
echo "API endpoint: http://$(hostname -I | cut -d' ' -f1):4567"