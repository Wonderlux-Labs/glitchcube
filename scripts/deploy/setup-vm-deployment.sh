#!/bin/bash
# Setup script for Home Assistant VM deployment
# Run this inside the VM to set up the deployment infrastructure

set -e

echo "🏠 Home Assistant VM Deployment Setup"
echo "===================================="

# Configuration
REPO_URL="https://github.com/YOUR_ORG/glitchcube.git"  # Update this!
REPO_DIR="/home/homeassistant/glitchcube_repo"
SCRIPT_DIR="/usr/local/bin"
SCRIPT_NAME="update_ha_config.sh"

# Create homeassistant user if it doesn't exist
if ! id -u homeassistant >/dev/null 2>&1; then
    echo "Creating homeassistant user..."
    sudo useradd -m -s /bin/bash homeassistant
fi

# Clone the repository
if [ ! -d "$REPO_DIR" ]; then
    echo "Cloning repository to $REPO_DIR..."
    sudo -u homeassistant git clone "$REPO_URL" "$REPO_DIR"
else
    echo "Repository already exists at $REPO_DIR"
fi

# Copy the update script
echo "Installing update script..."
sudo cp "$REPO_DIR/scripts/vm-update-ha-config.sh" "$SCRIPT_DIR/$SCRIPT_NAME"
sudo chmod +x "$SCRIPT_DIR/$SCRIPT_NAME"
sudo chown homeassistant:homeassistant "$SCRIPT_DIR/$SCRIPT_NAME"

# Create log directory
echo "Creating log directory..."
sudo mkdir -p /var/log
sudo touch /var/log/ha_config_updater.log
sudo chown homeassistant:homeassistant /var/log/ha_config_updater.log

# Set up Home Assistant shell command
echo "Configuring Home Assistant..."
cat << 'EOF'

Add this to your Home Assistant configuration.yaml:

shell_command:
  update_from_git: '/usr/local/bin/update_ha_config.sh'

And add/update this automation:

automation:
  - alias: "GitHub Deploy via Local Git"
    description: "Pull from GitHub when webhook is triggered"
    trigger:
      - platform: webhook
        webhook_id: github_deploy_trigger
        allowed_methods:
          - POST
        local_only: false
    action:
      - service: shell_command.update_from_git
      - service: persistent_notification.create
        data:
          title: "Deployment Started"
          message: "Pulling latest configuration from GitHub..."

EOF

echo ""
echo "✅ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Update the REPO_URL in this script and re-run if needed"
echo "2. Add the shell_command and automation to your HA config"
echo "3. Restart Home Assistant"
echo "4. Test by triggering the webhook"
echo ""
echo "Your webhook URL will be:"
echo "https://YOUR-HA-URL/api/webhook/github_deploy_trigger"