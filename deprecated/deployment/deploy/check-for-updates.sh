#!/bin/bash
# Check-for-updates script - checks if new commits are available on GitHub
# Can be run as a backup check or for monitoring
# Usage: ./scripts/check-for-updates.sh

set -e

REPO_PATH="/home/eric/glitchcube"
cd "$REPO_PATH"

# Get current commit
CURRENT_COMMIT=$(git rev-parse HEAD)

# Fetch latest changes (without merging)
git fetch origin main --quiet

# Get latest remote commit  
REMOTE_COMMIT=$(git rev-parse origin/main)

# Check if update needed
if [ "$CURRENT_COMMIT" != "$REMOTE_COMMIT" ]; then
    echo "🆕 Updates available!"
    echo "   Current: ${CURRENT_COMMIT:0:7}"
    echo "   Remote:  ${REMOTE_COMMIT:0:7}"
    echo ""
    echo "To deploy: rake deploy:pull"
    exit 0
else
    echo "✅ Already up to date (${CURRENT_COMMIT:0:7})"
    exit 1  # Exit 1 to indicate no updates
fi