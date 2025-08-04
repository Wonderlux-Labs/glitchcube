# Use Alpine Linux for minimal footprint
FROM ruby:3.3-alpine

# Install dependencies for building native extensions
RUN apk add --no-cache \
    build-base \
    git \
    tzdata \
    curl

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

# Create non-root user to run the app
RUN adduser -D -s /bin/sh glitchcube && \
    chown -R glitchcube:glitchcube /app

# Create data directories with proper permissions
RUN mkdir -p /app/data/context_documents /app/data/memories && \
    chown -R glitchcube:glitchcube /app/data

# Switch to non-root user
USER glitchcube

# Expose Sinatra port
EXPOSE 4567

# Health check endpoint
HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:4567/health || exit 1

# Start the application
CMD ["bundle", "exec", "ruby", "app.rb"]