#!/bin/bash

# Test script for Glitch Cube endpoints
set -e

echo "Starting Glitch Cube server..."
echo "Testing basic endpoints..."

# Use absolute path for asdf
ASDF="/opt/homebrew/bin/asdf"

# Start server in background
$ASDF exec bundle exec ruby app.rb &
SERVER_PID=$!

# Wait for server to start
sleep 2

# Test health endpoint
echo -e "\n=== Testing /health endpoint ==="
curl -s http://localhost:4567/health | jq

# Test root endpoint
echo -e "\n=== Testing / endpoint ==="
curl -s http://localhost:4567/ | jq

# Test /api/v1/test with greeting
echo -e "\n=== Testing /api/v1/test with greeting ==="
curl -s -X POST http://localhost:4567/api/v1/test \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello Glitch Cube!"}' | jq

# Test /api/v1/test with status check
echo -e "\n=== Testing /api/v1/test with status check ==="
curl -s -X POST http://localhost:4567/api/v1/test \
  -H "Content-Type: application/json" \
  -d '{"message": "What is your status?"}' | jq

# Kill server
kill $SERVER_PID

echo -e "\nServer stopped."