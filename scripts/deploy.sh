#!/bin/bash

# Deploy script - commits changes and deploys to glitchcube
# Usage: ./scripts/deploy.sh "commit message"

set -e  # Exit on any error

# Check if commit message is provided
if [ -z "$1" ]; then
    echo "Usage: $0 \"commit message\""
    echo "Example: $0 \"Add file editor container configuration\""
    exit 1
fi

COMMIT_MESSAGE="$1"
REMOTE_HOST="eric@glitchcube.local"
REMOTE_PATH="/home/eric/glitchcube"

echo "🔄 Starting deployment process..."

# Stage all changes
echo "📝 Adding changes to git..."
git add .

# Check if there are any changes to commit
if git diff --cached --quiet; then
    echo "ℹ️  No changes to commit"
else
    # Commit with provided message
    echo "💾 Committing changes..."
    git commit -m "$COMMIT_MESSAGE"
fi

# Push to remote repository
echo "⬆️  Pushing to remote repository..."
git push

# Deploy to glitchcube via SSH
echo "🚀 Deploying to glitchcube.local..."
ssh "$REMOTE_HOST" "cd $REMOTE_PATH && git pull && \
    if [ -d 'config/homeassistant' ]; then \
        echo '📁 Updating Home Assistant configuration files...'; \
        if docker-compose ps | grep -q homeassistant; then \
            echo '🗑️  Removing old HA config files from container...'; \
            docker exec glitchcube_homeassistant find /config \\( -name '*.yaml' -o -name '*.yml' \\) -not -path '/config/.storage/*' -delete 2>/dev/null || true; \
            docker exec glitchcube_homeassistant rm -rf /config/automations /config/scripts /config/sensors /config/template /config/input_helpers 2>/dev/null || true; \
            echo '📋 Copying new HA config files to container...'; \
            docker cp config/homeassistant/. glitchcube_homeassistant:/config/; \
            echo '🔄 Restarting Home Assistant to load new config...'; \
            docker-compose restart homeassistant; \
        fi; \
    fi && \
    if [ -d 'homeassistant_components' ]; then \
        echo '🏠 Installing Home Assistant custom components...'; \
        mkdir -p data/production/homeassistant/custom_components; \
        sudo rm -rf data/production/homeassistant/custom_components/glitchcube_conversation 2>/dev/null || true; \
        cp -r homeassistant_components/* data/production/homeassistant/custom_components/; \
        if docker-compose ps | grep -q homeassistant; then \
            echo '🔧 Installing custom components into running HA container...'; \
            for component in homeassistant_components/*/; do \
                component_name=\$(basename \"\$component\"); \
                echo \"   Installing: \$component_name\"; \
                docker cp \"\$component\" glitchcube_homeassistant:/config/custom_components/; \
            done; \
        fi; \
    fi && \
    echo '✅ Deployment complete!'"

echo "🎉 Successfully deployed to glitchcube!"