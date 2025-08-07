# Mac Mini Startup Scripts

## Overview

These scripts ensure all Glitch Cube services start automatically when the Mac Mini boots or reboots.

## Components

### 1. `mac_mini_startup.sh`
Main startup script that:
- Checks and starts Redis
- Checks and starts PostgreSQL
- Starts VMware Fusion
- Starts Home Assistant VM
- Waits for Home Assistant to be ready
- Starts Glitch Cube application with foreman

### 2. `com.glitchcube.startup.plist`
LaunchAgent configuration that runs the startup script at boot

### 3. `install_mac_mini_startup.sh`
Installation script that sets up the automatic startup

### 4. `check_mac_mini_health.sh`
Health check script to verify all services are running

## Installation

### From Development Machine
```bash
cd /Users/estiens/code/glitchcube/scripts
./install_mac_mini_startup.sh
```

This will:
1. Copy scripts to the Mac Mini
2. Install the LaunchAgent
3. Configure automatic startup

### Manual Installation on Mac Mini
```bash
ssh eristmini@speedygonzo
cd /Users/eristmini/glitch/glitchcube/scripts

# Make scripts executable
chmod +x mac_mini_startup.sh
chmod +x check_mac_mini_health.sh

# Install LaunchAgent
cp com.glitchcube.startup.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.glitchcube.startup.plist
```

## Usage

### Manual Startup
Run the startup sequence manually:
```bash
/Users/eristmini/glitch/glitchcube/scripts/mac_mini_startup.sh
```

### Health Check
Check if all services are running:
```bash
/Users/eristmini/glitch/glitchcube/scripts/check_mac_mini_health.sh
```

### Service Management
```bash
# Check service status
launchctl list | grep glitchcube

# Stop the service
launchctl unload ~/Library/LaunchAgents/com.glitchcube.startup.plist

# Start the service
launchctl load ~/Library/LaunchAgents/com.glitchcube.startup.plist

# Restart the service
launchctl unload ~/Library/LaunchAgents/com.glitchcube.startup.plist
launchctl load ~/Library/LaunchAgents/com.glitchcube.startup.plist
```

## Configuration

Edit these variables in `mac_mini_startup.sh`:

```bash
GLITCHCUBE_DIR="/Users/eristmini/glitch/glitchcube"
HASS_VM_IP="192.168.1.100"  # Your Home Assistant VM IP
HASS_VM_NAME="Home Assistant"  # VMware VM name
```

## Log Files

Startup logs are written to:
- `/Users/eristmini/glitch/startup.log` - Main startup log
- `/Users/eristmini/glitch/startup_stdout.log` - Standard output
- `/Users/eristmini/glitch/startup_stderr.log` - Error output
- `/Users/eristmini/glitch/glitchcube/logs/foreman.log` - Foreman process logs

## Troubleshooting

### Service Won't Start
1. Check logs: `tail -f /Users/eristmini/glitch/startup*.log`
2. Verify paths in scripts are correct
3. Ensure all dependencies are installed (Redis, PostgreSQL, VMware)

### Home Assistant Not Responding
1. Check VM is running: `vmrun list`
2. Verify IP address is correct
3. Check VMware network settings

### Database Connection Issues
1. Check PostgreSQL is running: `pg_isready`
2. Verify database exists: `psql -U postgres -l`
3. Check `.env.production` has correct settings

### Glitch Cube Not Starting
1. Check Ruby/bundler installed: `which ruby && which bundle`
2. Verify gems installed: `cd /Users/eristmini/glitch/glitchcube && bundle check`
3. Check foreman logs: `tail -f logs/foreman.log`

## Manual Service Startup Order

If automatic startup fails, manually start services in this order:

1. **Redis**
   ```bash
   brew services start redis
   redis-cli ping  # Should return PONG
   ```

2. **PostgreSQL**
   ```bash
   brew services start postgresql@14
   pg_isready  # Should show accepting connections
   ```

3. **VMware & Home Assistant**
   ```bash
   open -a "VMware Fusion"
   # Start VM from VMware UI or:
   vmrun start "/path/to/vm.vmx" nogui
   ```

4. **Glitch Cube**
   ```bash
   cd /Users/eristmini/glitch/glitchcube
   foreman start
   ```

## Remote Management

### SSH to Mac Mini
```bash
ssh eristmini@speedygonzo
```

### Check Status Remotely
```bash
ssh eristmini@speedygonzo "/Users/eristmini/glitch/glitchcube/scripts/check_mac_mini_health.sh"
```

### Restart Services Remotely
```bash
ssh eristmini@speedygonzo "launchctl unload ~/Library/LaunchAgents/com.glitchcube.startup.plist && launchctl load ~/Library/LaunchAgents/com.glitchcube.startup.plist"
```

## Security Notes

- Scripts run as user `eristmini`, not root
- Passwords should be in `.env` files, not scripts
- SSH keys recommended over passwords for remote access
- VMware VM should have restricted network access