# Use Alpine Linux for minimal footprint
FROM ruby:3.3-alpine

# Install dependencies for building native extensions
# sqlite-dev, pkgconfig, linux-headers needed for SQLite3 gem compilation
RUN apk add --no-cache \
    build-base \
    git \
    tzdata \
    curl \
    sqlite-dev \
    pkgconfig \
    linux-headers

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

# Create non-root user first
RUN adduser -D -s /bin/sh glitchcube

# Create data directories with correct ownership from the start
RUN mkdir -p /app/data/context_documents /app/data/memories && \
    chown -R glitchcube:glitchcube /app/data

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