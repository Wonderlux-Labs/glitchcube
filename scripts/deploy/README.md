# Deployment Scripts

This directory contains all deployment-related scripts for Glitch Cube.

## Current Deployment Architecture (Mac mini VM)

- **Home Assistant**: Runs in a VM, pulls from GitHub directly
- **Sinatra**: Runs on Mac host, has `/deploy` webhook endpoint
- **No shared folders**: Each system manages its own git repository

## Scripts

### VM Deployment (Home Assistant)

- **`vm-update-ha-config.sh`** - Main deployment script that runs INSIDE the VM
  - Pulls from GitHub to `/home/homeassistant/glitchcube_repo`
  - Copies only HA config files to `/config/`
  - Validates configuration and restarts HA
  - Called by HA automation via shell_command

- **`setup-vm-deployment.sh`** - Initial setup script for the VM
  - Clones the repository
  - Installs the update script
  - Provides configuration instructions

### Legacy Docker/Pi Deployment

These scripts are for the original Raspberry Pi Docker deployment:

- **`pull-from-github.sh`** - Pulls and deploys on Raspberry Pi
  - Used by Docker-based deployments
  - Updates containers and copies configs

- **`push-to-production.sh`** - Commits, pushes, and deploys via SSH
  - For manual deployments from development machine
  - SSHs to Pi and runs deployment

- **`check-for-updates.sh`** - Checks if new commits are available
  - Can be used for monitoring
  - Returns exit code 0 if updates available

### Systemd Configuration (Pi)

- **`glitchcube-auto-deploy.service`** - Systemd service definition
- **`glitchcube-auto-deploy.timer`** - Systemd timer for periodic checks

### Home Assistant Configuration

- **`ha-deploy-webhook.yaml`** - Example HA automation for webhook deployment
  - Shows how to configure HA to respond to deployment webhooks

## Deployment Workflows

### Mac mini VM Setup
1. GitHub push → GitHub Actions
2. Actions calls two webhooks:
   - HA webhook → runs `vm-update-ha-config.sh`
   - Sinatra webhook → pulls and restarts
3. Each system updates independently

### Legacy Pi/Docker Setup
1. GitHub push → GitHub Actions
2. Actions SSHs to Pi
3. Runs `pull-from-github.sh`
4. Updates Docker containers

## Which Scripts to Use?

- **For Mac mini VM**: Use `vm-update-ha-config.sh` and `setup-vm-deployment.sh`
- **For Raspberry Pi Docker**: Use `pull-from-github.sh` and related scripts
- **For development**: Use `push-to-production.sh` for manual deploys