FROM ruby:3.3-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    build-essential \
    git \
    curl \
    libsqlite3-dev \
    libmariadb-dev \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy gem definitions and install dependencies
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local deployment 'true' && \
    bundle config set --local without 'development test' && \
    bundle install --jobs 4

# Copy the rest of the application code
# The .dockerignore file prevents /data and /logs from being copied
COPY . .

# Create placeholder directories for volumes and set permissions
# These will be overlaid by volume mounts at runtime
RUN mkdir -p /app/data/context_documents /app/data/memories /app/logs && \
    adduser --disabled-password --gecos '' glitchcube && \
    chown -R glitchcube:glitchcube /app

# Switch to the non-root user
USER glitchcube

EXPOSE 4567

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD curl -f http://localhost:4567/health || exit 1

CMD ["bundle", "exec", "ruby", "app.rb"]