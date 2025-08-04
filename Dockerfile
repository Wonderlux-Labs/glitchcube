# Use Debian base to match production Raspberry Pi
FROM ruby:3.3-slim

# Install dependencies for building native extensions
# Simple apt install approach for Raspberry Pi compatibility
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    curl \
    libsqlite3-dev \
    libmariadb-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

# Create app directory
WORKDIR /app

# Copy Gemfile first for better caching
COPY Gemfile Gemfile.lock ./

# Install gems
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4

# Create non-root user first (Debian syntax)
RUN adduser --disabled-password --gecos '' glitchcube

# Copy application code (excluding data directories via .dockerignore)
COPY . .

# Remove any data directories that might have been copied despite .dockerignore
RUN rm -rf /app/data/production /app/data/development /app/logs || true

# Create data and logs directories with correct ownership from the start
RUN mkdir -p /app/data/context_documents /app/data/memories /app/logs && \
    chown -R glitchcube:glitchcube /app/data /app/logs && \
    chmod -R 755 /app/logs

# Only change ownership of essential app files (avoid vendor/ and other large dirs)
RUN chown glitchcube:glitchcube /app/app.rb /app/config.ru /app/Gemfile* && \
    test -d /app/lib && chown -R glitchcube:glitchcube /app/lib || true && \
    test -d /app/config && chown -R glitchcube:glitchcube /app/config || true

# Switch to non-root user
USER glitchcube

# Expose Sinatra port
EXPOSE 4567

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:4567/health || exit 1

# Start the application
CMD ["bundle", "exec", "ruby", "app.rb"]