#!/bin/bash
# Setup script for deployment configuration

echo "🔧 Glitch Cube Deployment Setup"
echo "================================"

# Create .env.deployment if it doesn't exist
if [ ! -f .env.deployment ]; then
  echo "Creating .env.deployment file..."
  cat > .env.deployment << 'EOF'
# Home Assistant VM Configuration
HASS_VM_HOST=192.168.1.100  # Update with your VM's IP
HASS_VM_USER=homeassistant   # Update with your VM user

# Host System Configuration  
SINATRA_HOST=localhost
SINATRA_PORT=4567

# GitHub Webhook (for Home Assistant)
HASS_WEBHOOK_URL=http://your-ha-external-ip:8123/api/webhook/deployment_ready
EOF
  echo "✅ Created .env.deployment - Please update with your actual values"
else
  echo "✅ .env.deployment already exists"
fi

# Load environment variables
if [ -f .env.deployment ]; then
  export $(cat .env.deployment | grep -v '^#' | xargs)
fi

echo ""
echo "📋 Current Configuration:"
echo "  Home Assistant VM: ${HASS_VM_USER}@${HASS_VM_HOST}"
echo "  Sinatra Port: ${SINATRA_PORT}"
echo ""

# Test connectivity
echo "🔍 Testing connections..."

# Test SSH to VM
echo -n "  VM SSH: "
if ssh -o ConnectTimeout=5 ${HASS_VM_USER}@${HASS_VM_HOST} 'exit' 2>/dev/null; then
  echo "✅ Connected"
else
  echo "❌ Failed"
  echo ""
  echo "💡 To setup passwordless SSH:"
  echo "  rake hass:setup_ssh"
fi

# Test local Sinatra
echo -n "  Sinatra: "
if curl -s http://localhost:${SINATRA_PORT}/health > /dev/null 2>&1; then
  echo "✅ Running"
else
  echo "⚠️  Not running"
  echo ""
  echo "💡 To start Sinatra:"
  echo "  rake host:dev  # Development mode"
  echo "  rake host:restart  # Production mode"
fi

echo ""
echo "📚 Available Deployment Commands:"
echo ""
echo "  Manual deployment:"
echo "    rake hass:deploy         # Deploy HA config to VM"
echo "    rake hass:pull           # Pull HA config from VM"
echo "    rake hass:quick          # Quick sync without restart"
echo "    rake host:deploy         # Deploy Sinatra (pull + restart)"
echo "    rake deploy:full         # Deploy everything"
echo ""
echo "  Status checks:"
echo "    rake hass:status         # Check HA VM status"
echo "    rake host:status         # Check Sinatra status"
echo "    rake deploy:check        # Check if deployment needed"
echo ""
echo "  GitHub Actions:"
echo "    - Push to main branch"
echo "    - Tests pass"
echo "    - Webhook sent to HA"
echo "    - HA triggers deployment"
echo ""
echo "💡 Your ideal workflow:"
echo "  1. Push to GitHub from any IP"
echo "  2. GitHub Actions runs tests"
echo "  3. On green build, webhook sent to HA (external IP)"
echo "  4. HA automation triggers host deployment"
echo "  5. Host pulls git changes and restarts Sinatra"
echo "  6. Host deploys HA config via SCP to VM"
echo "  7. HA restarts with new config"
echo ""

# Quick test of manual deployment
echo "🧪 Test manual deployment?"
echo "  This will:"
echo "  - Check git status"
echo "  - Show what would be deployed"
echo "  - NOT actually deploy anything"
echo ""
read -p "Run test? [y/N]: " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo ""
  echo "Running deployment check..."
  bundle exec rake deploy:check
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "📖 Next steps:"
echo "  1. Update .env.deployment with your actual IPs/hosts"
echo "  2. Setup SSH keys: rake hass:setup_ssh"
echo "  3. Test manual deploy: rake hass:deploy"
echo "  4. Configure GitHub secrets for webhook URL"