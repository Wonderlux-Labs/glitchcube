#!/bin/bash
# Update script for Glitch Cube - handles git pull and component deployment

set -e

echo "🎲 Updating Glitch Cube..."
echo "=========================="

# Navigate to the script's directory
cd "$(dirname "$0")/.."

# Git pull
echo "📥 Pulling latest changes..."
git pull

# Rebuild containers if needed
echo "🔨 Rebuilding containers..."
docker-compose build

# Copy Home Assistant custom components to data folder
if [ -d "homeassistant_components" ]; then
    echo "🏠 Updating Home Assistant custom components..."
    mkdir -p data/production/homeassistant/custom_components
    
    # Remove old components first to avoid conflicts
    rm -rf data/production/homeassistant/custom_components/glitchcube_conversation
    
    # Copy new components
    cp -r homeassistant_components/* data/production/homeassistant/custom_components/
    echo "✅ Updated custom components: $(ls homeassistant_components/)"
    
    # Copy components into running Home Assistant container
    if docker-compose ps | grep -q homeassistant; then
        echo "🔧 Installing components into running Home Assistant container..."
        for component in homeassistant_components/*/; do
            component_name=$(basename "$component")
            echo "   Installing: $component_name"
            docker cp "$component" glitchcube_homeassistant:/config/custom_components/
        done
        
        echo "🔄 Restarting Home Assistant to load updated components..."
        docker-compose restart homeassistant
    fi
fi

# Restart services
echo "🔄 Restarting services..."
docker-compose -f docker-compose.yml -f docker-compose.production.yml up -d

echo "✅ Update complete!"
echo ""
echo "📊 Service status:"
docker-compose ps