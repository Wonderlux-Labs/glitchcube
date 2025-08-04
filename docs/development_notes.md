# Development Notes

This document contains helpful tips, workarounds, and solutions for common development issues.

## macOS Development Setup

### Installing mysql2 gem on macOS

After installing MySQL via Homebrew (`brew install mysql`), the mysql2 gem often fails to install due to missing headers and libraries. Use this command to install it successfully:

```bash
CFLAGS="-I$(brew --prefix mysql)/include/mysql" \
LDFLAGS="-L$(brew --prefix mysql)/lib -L$(brew --prefix openssl)/lib" \
gem install mysql2 -- --with-mysql-lib=$(brew --prefix mysql)/lib \
                    --with-mysql-dir=$(brew --prefix mysql) \
                    --with-mysql-include=$(brew --prefix mysql)/include/mysql \
                    --with-ssl-dir=$(brew --prefix openssl)
```

This command:
- Sets the proper C compiler flags to find MySQL headers
- Sets linker flags for MySQL and OpenSSL libraries  
- Passes the correct directory paths to the gem installer

### Other macOS Tips

- Python might be `python3` instead of `python`
- Some GNU tools have different names (e.g., `gsed` instead of `sed`)
- Use `brew services` to manage background services
- System Integrity Protection (SIP) may block certain operations

## Docker Development

### Running without Docker Desktop

If you prefer not to use Docker Desktop on macOS:
- Consider using `colima` as a Docker Desktop alternative
- Or use `docker-machine` with VirtualBox

### Docker Compose Tips

- Use `docker-compose logs -f [service]` to tail logs for a specific service
- Add `--build` flag to force rebuild: `docker-compose up --build`
- Use `.env` file for environment variables instead of exporting them

## Ruby/Rails Development

### Bundle Install Issues

If you encounter issues with `bundle install`:
- Try `bundle config set --local path 'vendor/bundle'` to install gems locally
- Use `bundle config build.nokogiri --use-system-libraries` for Nokogiri issues
- Clear bundle cache with `bundle clean --force`

### Debugging Tips

- Use `binding.pry` for interactive debugging (add `pry` to Gemfile)
- Enable verbose mode in Sinatra: `set :logging, true`
- Check Sidekiq web UI at `http://localhost:4567/sidekiq`

## Home Assistant Development

### Testing REST API

Test the REST API integration:
```bash
# Health check
curl -X GET http://localhost:4567/health

# Test conversation endpoint
curl -X POST http://localhost:4567/api/v1/conversation \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello", "session_id": "test"}'
```

### Mock Mode

Set `MOCK_HOME_ASSISTANT=true` in `.env` to run without a real Home Assistant instance.

## Git Workflow

### Deployment Commands

- **Push to production**: `rake deploy:push["commit message"]` or `./scripts/push-to-production.sh "message"`
- **Pull on device**: `rake deploy:pull` or `./scripts/pull-from-github.sh`
- **Check for updates**: `rake deploy:check` or `./scripts/check-for-updates.sh`

### Useful Git Aliases

Add to `~/.gitconfig`:
```
[alias]
    st = status
    co = checkout
    br = branch
    last = log -1 HEAD
    unstage = reset HEAD --
```

## Troubleshooting

### Port Conflicts

If you get "address already in use" errors:
```bash
# Find process using port 4567
lsof -i :4567

# Kill process
kill -9 [PID]
```

### Redis Connection Issues

If Redis won't connect:
- Check if Redis is running: `redis-cli ping`
- Check Redis logs: `docker-compose logs redis`
- Ensure `REDIS_URL` is set correctly in `.env`

### OpenRouter API Issues

- Always check your API key is valid
- Monitor rate limits in responses
- Use cheaper models for development/testing
- Check the Helicone dashboard for request logs

## Performance Tips

### Ruby Performance

- Use `ruby-prof` gem for profiling
- Enable `frozen_string_literal: true` in Ruby files
- Use symbols instead of strings for hash keys
- Avoid N+1 queries in database operations

### Docker Performance on macOS

- Increase Docker Desktop memory allocation
- Use volumes for better I/O performance
- Exclude `node_modules` and `vendor` from volume mounts

## Testing

### Running Specific Tests

```bash
# Run single test file
bundle exec rspec spec/services/weather_service_spec.rb

# Run specific test by line number
bundle exec rspec spec/services/weather_service_spec.rb:42

# Run tests matching pattern
bundle exec rspec -e "updates weather summary"
```

### VCR Cassettes

- Delete cassettes to re-record: `rm spec/vcr_cassettes/*.yml`
- Set `VCR_RECORD_MODE=all` to force re-recording
- Review cassettes for sensitive data before committing

## Useful Resources

- [Sinatra Documentation](http://sinatrarb.com/)
- [Home Assistant REST API](https://developers.home-assistant.io/docs/api/rest)
- [OpenRouter API Docs](https://openrouter.ai/docs)
- [Sidekiq Best Practices](https://github.com/mperham/sidekiq/wiki/Best-Practices)