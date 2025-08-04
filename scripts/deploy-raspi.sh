#!/bin/bash
# Deployment script for Glitch Cube on Raspberry Pi 5
# Run with: bash deploy-raspi.sh

set -e

echo "🎲 Glitch Cube Deployment Script for Raspberry Pi 5"
echo "=================================================="

# Check if running on Raspberry Pi
if ! grep -q "Raspberry Pi" /proc/cpuinfo 2>/dev/null; then
    echo "⚠️  Warning: This doesn't appear to be a Raspberry Pi"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "📦 Docker not found. Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
    echo "✅ Docker installed. Please log out and back in, then run this script again."
    exit 0
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "📦 Installing Docker Compose..."
    sudo apt update
    sudo apt install -y docker-compose
fi

# Check system resources
echo "🔍 Checking system resources..."
TOTAL_MEM=$(free -g | awk '/^Mem:/{print $2}')
if [ "$TOTAL_MEM" -lt 4 ]; then
    echo "⚠️  Warning: System has less than 4GB RAM. Performance may be limited."
fi

# Create data directories
echo "📁 Creating data directories..."
mkdir -p data/production/{homeassistant,glitchcube,context_documents,postgres}
mkdir -p data/development/{glitchcube,context_documents}
mkdir -p data/test/{glitchcube,context_documents}
mkdir -p data/{redis,portainer}

# Copy initial context documents if they exist
if [ -d "data/context_documents" ]; then
    echo "📄 Copying initial context documents..."
    cp -r data/context_documents/* data/production/context_documents/ 2>/dev/null || true
fi

# Check for .env file
if [ ! -f .env ]; then
    if [ -f .env.production.example ]; then
        echo "📝 Creating .env from example..."
        cp .env.production.example .env
        
        # Generate session secret if not set
        if grep -q "generate_a_64_character_hex_string_here" .env; then
            echo "🔐 Generating session secret..."
            # Use openssl which is more likely to be available on Pi
            SECRET=$(openssl rand -hex 64)
            sed -i "s/generate_a_64_character_hex_string_here/$SECRET/g" .env
        fi
        
        echo "⚠️  Please edit .env and configure:"
        echo "   - OPENROUTER_API_KEY (required)"
        echo "   - MASTER_PASSWORD (change from default 'glitchcube123')"
        echo "   - HA_TOKEN (will be generated after Home Assistant setup)"
        read -p "Press Enter to continue after editing .env..."
    else
        echo "❌ Error: .env.production.example not found"
        exit 1
    fi
fi

# Check if master password is set
if grep -q "glitchcube123" .env; then
    echo "⚠️  Using default master password 'glitchcube123'"
    echo "   You should change MASTER_PASSWORD in .env for security"
fi

# Build containers
echo "🔨 Building Docker containers..."
docker-compose build

# Start services with Portainer
echo "🚀 Starting services..."
docker-compose -f docker-compose.yml -f docker-compose.production.yml --profile management up -d

# Wait for services to be healthy
echo "⏳ Waiting for services to be healthy..."
sleep 10

# Check service status
echo "📊 Service status:"
docker-compose ps

# Set up systemd service for auto-start
read -p "Would you like to enable auto-start on boot? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🔧 Setting up systemd service..."
    CURRENT_DIR=$(pwd)
    
    sudo tee /etc/systemd/system/glitchcube.service > /dev/null <<EOF
[Unit]
Description=Glitch Cube Docker Compose Application
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$CURRENT_DIR
ExecStart=/usr/bin/docker-compose -f docker-compose.yml -f docker-compose.production.yml --profile management up
ExecStop=/usr/bin/docker-compose -f docker-compose.yml -f docker-compose.production.yml down
TimeoutStartSec=300
Restart=unless-stopped
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF
    
    sudo systemctl daemon-reload
    sudo systemctl enable glitchcube.service
    echo "✅ Auto-start enabled"
fi

# Set up Home Assistant token
echo ""
echo "📋 Next steps:"
echo "1. Access Home Assistant at http://$(hostname -I | cut -d' ' -f1):8123"
echo "2. Complete Home Assistant onboarding"
echo "3. Create a long-lived access token:"
echo "   - Go to your Home Assistant profile"
echo "   - Scroll to 'Long-Lived Access Tokens'"
echo "   - Create a new token and copy it"
echo "4. Add the token to your .env file as HA_TOKEN"
echo "5. Restart the services: docker-compose -f docker-compose.yml -f docker-compose.production.yml restart glitchcube sidekiq"
echo ""
echo "🎲 Glitch Cube is now running!"
echo "API endpoint: http://$(hostname -I | cut -d' ' -f1):4567"
echo "Portainer UI: https://$(hostname -I | cut -d' ' -f1):9443 (admin / MASTER_PASSWORD from .env)"
echo ""
echo "View logs: docker-compose -f docker-compose.yml -f docker-compose.production.yml logs -f"
echo "Stop services: docker-compose -f docker-compose.yml -f docker-compose.production.yml down"
echo "Update: git pull && docker-compose build && docker-compose -f docker-compose.yml -f docker-compose.production.yml up -d"