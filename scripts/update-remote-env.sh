#!/bin/bash
# Script to update remote .env file for host networking configuration

echo "Updating remote .env file for host networking..."

# Update HA_URL to use localhost (host networking)
if grep -q "HA_URL=" .env; then
    sed -i.bak 's|HA_URL=http://host\.docker\.internal:8123|HA_URL=http://localhost:8123|g' .env
    sed -i.bak 's|HA_URL=http://glitchcube\.local:8123|HA_URL=http://localhost:8123|g' .env
    echo "Updated HA_URL to use localhost"
else
    echo "HA_URL=http://localhost:8123" >> .env
    echo "Added HA_URL to .env"
fi

# Update REDIS_URL to use localhost (host networking)
if grep -q "REDIS_URL=" .env; then
    sed -i.bak 's|REDIS_URL=redis://redis:6379/0|REDIS_URL=redis://localhost:6379/0|g' .env
    echo "Updated REDIS_URL to use localhost"
else
    echo "REDIS_URL=redis://localhost:6379/0" >> .env
    echo "Added REDIS_URL to .env"
fi

echo "Remote .env file updated for host networking configuration"
echo "All containers now communicate via localhost"