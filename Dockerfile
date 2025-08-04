# Use Debian base to match production Raspberry Pi
FROM ruby:3.3-slim

# Install dependencies for building native extensions
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

# Copy application code
COPY . .

# Create directories
RUN mkdir -p /app/data/context_documents /app/data/memories /app/logs

# Create non-root user and set ownership
RUN adduser --disabled-password --gecos '' glitchcube && \
    chown -R glitchcube:glitchcube /app

# Switch to non-root user
USER glitchcube

# Expose Sinatra port
EXPOSE 4567

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:4567/health || exit 1

# Start the application
CMD ["bundle", "exec", "ruby", "app.rb"]