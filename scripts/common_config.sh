#!/bin/bash

# Common configuration for all GlitchCube scripts
# Provides consistent paths, hosts, and functions

# Paths
export GLITCHCUBE_DIR="/Users/eristmini/glitch/glitchcube"
export GLITCHCUBE_USER="eristmini"
export LOG_DIR="/Users/eristmini/glitch"

# Host configurations with Tailscale primary, .local fallback
# Mac Mini (host system)
export MAC_MINI_HOST="speedygonzo.pumpkinseed-smoot.ts.net"
export MAC_MINI_HOST_FALLBACK="speedygonzo.local"
export MAC_MINI_USER="eristmini"

# Home Assistant VM
export HASS_HOST="glitch.pumpkinseed-smoot.ts.net"
export HASS_HOST_FALLBACK="glitch.local"
export HASS_USER="root"

# Function to get reachable host
get_reachable_host() {
    local primary=$1
    local fallback=$2
    
    # Try primary first (Tailscale)
    if ping -c 1 -W 1 "$primary" >/dev/null 2>&1; then
        echo "$primary"
    elif ping -c 1 -W 1 "$fallback" >/dev/null 2>&1; then
        echo "$fallback"
    else
        echo "$primary"  # Default to primary if neither responds
    fi
}

# Get current hosts
export CURRENT_MAC_HOST=$(get_reachable_host "$MAC_MINI_HOST" "$MAC_MINI_HOST_FALLBACK")
export CURRENT_HASS_HOST=$(get_reachable_host "$HASS_HOST" "$HASS_HOST_FALLBACK")

# Common logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

log_success() {
    echo -e "\033[0;32m✓\033[0m $1"
}

log_error() {
    echo -e "\033[0;31m✗\033[0m $1"
}

log_info() {
    echo -e "\033[1;33m➜\033[0m $1"
}