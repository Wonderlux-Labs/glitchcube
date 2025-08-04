#!/bin/bash
# Install Glitch Cube Voice Integration into Home Assistant

set -e

echo "Installing Glitch Cube Voice Integration..."

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "Error: Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if Home Assistant container is running
if ! docker-compose ps homeassistant | grep -q "Up"; then
    echo "Error: Home Assistant container is not running. Please start it with 'docker-compose up -d homeassistant'"
    exit 1
fi

# Create the custom component directory
echo "Creating custom component directory..."
docker-compose exec homeassistant mkdir -p /config/custom_components/glitchcube_conversation

# Copy all files
echo "Copying integration files..."
docker cp config/home_assistant/custom_components/glitchcube_conversation/__init__.py glitchcube-homeassistant-1:/config/custom_components/glitchcube_conversation/
docker cp config/home_assistant/custom_components/glitchcube_conversation/manifest.json glitchcube-homeassistant-1:/config/custom_components/glitchcube_conversation/
docker cp config/home_assistant/custom_components/glitchcube_conversation/const.py glitchcube-homeassistant-1:/config/custom_components/glitchcube_conversation/
docker cp config/home_assistant/custom_components/glitchcube_conversation/config_flow.py glitchcube-homeassistant-1:/config/custom_components/glitchcube_conversation/
docker cp config/home_assistant/custom_components/glitchcube_conversation/conversation.py glitchcube-homeassistant-1:/config/custom_components/glitchcube_conversation/
docker cp config/home_assistant/custom_components/glitchcube_conversation/strings.json glitchcube-homeassistant-1:/config/custom_components/glitchcube_conversation/

echo "Setting proper permissions..."
docker-compose exec homeassistant chown -R root:root /config/custom_components/glitchcube_conversation
docker-compose exec homeassistant chmod -R 644 /config/custom_components/glitchcube_conversation/*.py
docker-compose exec homeassistant chmod -R 644 /config/custom_components/glitchcube_conversation/*.json

echo "Installation complete!"
echo ""
echo "Next steps:"
echo "1. Restart Home Assistant: docker-compose restart homeassistant"
echo "2. Go to Settings > Devices & Services > Add Integration"
echo "3. Search for 'Glitch Cube Conversation Agent'"
echo "4. Configure with your Glitch Cube host (default: glitchcube.local:4567)"
echo "5. Set this as your default conversation agent in Settings > Voice assistants"