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
    if [ -d 'homeassistant_components' ]; then \
        echo '🏠 Installing Home Assistant custom components...'; \
        mkdir -p data/production/homeassistant/custom_components; \
        rm -rf data/production/homeassistant/custom_components/glitchcube_conversation; \
        cp -r homeassistant_components/* data/production/homeassistant/custom_components/; \
        if docker-compose ps | grep -q homeassistant; then \
            echo '🔧 Installing into running HA container...'; \
            for component in homeassistant_components/*/; do \
                component_name=\$(basename \"\$component\"); \
                echo \"   Installing: \$component_name\"; \
                docker cp \"\$component\" glitchcube_homeassistant:/config/custom_components/; \
            done; \
            echo '🔄 Restarting Home Assistant...'; \
            docker-compose restart homeassistant; \
        fi; \
    fi && \
    echo '✅ Deployment complete!'"

echo "🎉 Successfully deployed to glitchcube!"