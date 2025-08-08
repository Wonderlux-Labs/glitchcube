# Docker Development Guide

This guide covers Docker-based development workflows for Glitch Cube.

## Development with VS Code DevContainers

### Prerequisites
- VS Code with Remote-Containers extension
- Docker Desktop (Mac/Windows) or Docker Engine (Linux)

### Getting Started

1. **Open in DevContainer**
   ```bash
   code glitchcube/
   # When prompted, click "Reopen in Container"
   ```

2. **Automatic Setup**
   - Ruby environment with all dependencies
   - Mock Home Assistant enabled by default
   - Development mode enabled
   - Port forwarding configured

3. **Available Commands Inside Container**
   ```bash
   # Run the app (auto-reloads on file changes)
   bundle exec ruby app.rb
   
   # Run tests
   bundle exec rspec
   
   # Run linter
   bundle exec rubocop
   
   # Start interactive console
   bundle exec irb -r ./app.rb
   
   # Run Sidekiq
   bundle exec sidekiq
   ```

## Local Docker Development (without DevContainer)

### Start Development Stack
```bash
# Start with development overrides
docker-compose -f docker-compose.yml -f docker-compose.dev.yml up -d

# View logs
docker-compose logs -f glitchcube

# Access the container shell
docker-compose exec glitchcube bash
```

### Development Environment Variables
The development setup automatically sets:
- `RACK_ENV=development`
- `MOCK_HOME_ASSISTANT=true`
- `DEVELOPMENT_MODE=true`

### Hot Reloading
The development container mounts your local code directory, so changes are reflected immediately. However, you'll need to restart the Ruby process for changes to take effect:

```bash
# Inside the container
docker-compose exec glitchcube bash
bundle exec rerun -- ruby app.rb
```

## Testing with Docker

### Run Tests in Container
```bash
# Run all tests
docker-compose exec glitchcube bundle exec rspec

# Run specific test
docker-compose exec glitchcube bundle exec rspec spec/models/conversation_spec.rb

# Run with coverage
docker-compose exec -e COVERAGE=true glitchcube bundle exec rspec
```

### Testing Home Assistant Integration
```bash
# Test real HA connection (disable mock)
docker-compose exec -e MOCK_HOME_ASSISTANT=false glitchcube bundle exec ruby scripts/testing_scripts/test_ha_connection.rb

# Test mock HA endpoints
curl http://localhost:4567/mock_ha/api/states
```

## Debugging

### Interactive Debugging with Pry
1. Add `binding.pry` to your code
2. Run the app:
   ```bash
   docker-compose exec glitchcube bundle exec ruby app.rb
   ```
3. When breakpoint hits, you'll have an interactive console

### View Container Logs
```bash
# All containers
docker-compose logs -f

# Specific container with timestamps
docker-compose logs -f --timestamps glitchcube

# Last 100 lines
docker-compose logs --tail=100 glitchcube
```

### Debug Container Issues
```bash
# Check container status
docker-compose ps

# Inspect container
docker inspect glitchcube_app

# View resource usage
docker stats

# Execute commands in container
docker-compose exec glitchcube ls -la
docker-compose exec glitchcube bundle check
```

## Performance Profiling

### Memory Profiling
```bash
# Inside container
docker-compose exec glitchcube bash
bundle exec ruby-prof app.rb
```

### CPU Profiling
```bash
# Monitor container resources
docker stats glitchcube_app
```

## Common Development Tasks

### Update Dependencies
```bash
# Update Gemfile
docker-compose exec glitchcube bundle update

# Rebuild after Gemfile changes
docker-compose build glitchcube
```

### Database/Redis Operations
```bash
# Access Redis CLI
docker-compose exec redis redis-cli

# Monitor Redis
docker-compose exec redis redis-cli monitor

# Clear Redis
docker-compose exec redis redis-cli FLUSHALL
```

### Clean Slate
```bash
# Stop and remove containers
docker-compose down

# Remove volumes too (careful - deletes data!)
docker-compose down -v

# Rebuild everything
docker-compose build --no-cache
docker-compose up -d
```

## Tips and Tricks

### Speed Up Development
1. **Use volumes for gems**: Already configured in `docker-compose.dev.yml`
2. **Incremental builds**: Only rebuild what changed
   ```bash
   docker-compose build glitchcube
   ```

### Environment Switching
```bash
# Production-like environment
RACK_ENV=production docker-compose up -d

# With real Home Assistant
MOCK_HOME_ASSISTANT=false docker-compose up -d
```

### Shell Aliases
Add to your `.bashrc` or `.zshrc`:
```bash
alias dc='docker-compose'
alias dcr='docker-compose run --rm'
alias dce='docker-compose exec'
alias dcl='docker-compose logs -f'
alias gcube='docker-compose exec glitchcube'
```

## Troubleshooting

### Container won't start
```bash
# Check logs
docker-compose logs glitchcube

# Validate compose file
docker-compose config
```

### Permission issues
```bash
# Fix ownership (from host)
sudo chown -R $(id -u):$(id -g) .
```

### Port conflicts
```bash
# Find what's using port 4567
lsof -i :4567

# Use different port
PORT=4568 docker-compose up -d
```

### Slow performance on Mac
- Enable "Use the new Virtualization framework" in Docker Desktop
- Increase Docker Desktop memory allocation
- Use cached volume mounts (already configured)