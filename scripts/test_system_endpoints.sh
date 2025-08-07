#!/bin/bash

# Test script for system management endpoints

BASE_URL="${1:-http://localhost:4567}"
AUTH_TOKEN="${RESTART_AUTH_TOKEN:-change-me-in-production}"

echo "🧪 Testing System Management Endpoints"
echo "Base URL: $BASE_URL"
echo ""

# Test health endpoint
echo "1️⃣ Testing Health Endpoint..."
echo "GET $BASE_URL/api/v1/system/health"
curl -s "$BASE_URL/api/v1/system/health" | jq '.' || echo "Failed to get health"
echo ""

# Test restart history endpoint
echo "2️⃣ Testing Restart History Endpoint..."
echo "GET $BASE_URL/api/v1/system/restart_history"
curl -s "$BASE_URL/api/v1/system/restart_history" | jq '.' || echo "Failed to get history"
echo ""

# Test restart endpoint (dry run - comment out to actually trigger)
echo "3️⃣ Testing Restart Endpoint (displaying command only)..."
echo "POST $BASE_URL/api/v1/system/restart"
echo "Would send: {\"level\": \"soft\", \"reason\": \"test\", \"auth_token\": \"$AUTH_TOKEN\"}"
# Uncomment to actually trigger:
# curl -s -X POST "$BASE_URL/api/v1/system/restart" \
#   -H "Content-Type: application/json" \
#   -d "{\"level\": \"soft\", \"reason\": \"test\", \"auth_token\": \"$AUTH_TOKEN\"}" | jq '.'
echo ""

# Test clear queues endpoint (dry run - comment out to actually trigger)
echo "4️⃣ Testing Clear Queues Endpoint (displaying command only)..."
echo "POST $BASE_URL/api/v1/system/clear_queues"
echo "Would send: {\"auth_token\": \"$AUTH_TOKEN\"}"
# Uncomment to actually trigger:
# curl -s -X POST "$BASE_URL/api/v1/system/clear_queues" \
#   -H "Content-Type: application/json" \
#   -d "{\"auth_token\": \"$AUTH_TOKEN\"}" | jq '.'
echo ""

echo "✅ Test complete!"
echo ""
echo "To actually trigger restart or clear queues, edit this script and uncomment the curl commands."