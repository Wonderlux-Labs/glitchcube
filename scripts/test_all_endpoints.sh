#!/bin/bash

# Glitchcube API Endpoint Test Script
# Tests all API endpoints for basic connectivity and loading errors
# Usage: ./scripts/test_all_endpoints.sh

set -e

BASE_URL="http://localhost:4567"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
SUCCESS_COUNT=0
TOTAL_COUNT=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}  Glitchcube API Endpoint Test Suite${NC}"
echo -e "${BLUE}  Started at: $TIMESTAMP${NC}"
echo -e "${BLUE}  Base URL: $BASE_URL${NC}"
echo -e "${BLUE}===========================================${NC}"
echo ""

# Function to test GET endpoints
test_get() {
    local endpoint="$1"
    local description="$2"
    local expected_status="${3:-200}"
    
    ((TOTAL_COUNT++))
    echo -n "Testing GET $endpoint ($description)... "
    
    response=$(curl -s -w "\n%{http_code}" "$BASE_URL$endpoint" 2>/dev/null)
    status_code=$(echo "$response" | tail -n1)
    
    if [[ "$status_code" == "$expected_status" ]]; then
        echo -e "${GREEN}✓ $status_code${NC}"
        ((SUCCESS_COUNT++))
    else
        echo -e "${RED}✗ $status_code (expected $expected_status)${NC}"
    fi
}

# Function to test POST endpoints with JSON data
test_post() {
    local endpoint="$1"
    local description="$2"
    local data="$3"
    local expected_status="${4:-200}"
    
    ((TOTAL_COUNT++))
    echo -n "Testing POST $endpoint ($description)... "
    
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$data" \
        "$BASE_URL$endpoint" 2>/dev/null)
    status_code=$(echo "$response" | tail -n1)
    
    if [[ "$status_code" == "$expected_status" || "$status_code" == "400" || "$status_code" == "422" ]]; then
        # Accept 400/422 as valid responses for POST endpoints (missing required params)
        echo -e "${GREEN}✓ $status_code${NC}"
        ((SUCCESS_COUNT++))
    else
        echo -e "${RED}✗ $status_code (expected $expected_status or 4xx)${NC}"
    fi
}

# Function to test DELETE endpoints
test_delete() {
    local endpoint="$1"
    local description="$2"
    local expected_status="${3:-200}"
    
    ((TOTAL_COUNT++))
    echo -n "Testing DELETE $endpoint ($description)... "
    
    response=$(curl -s -w "\n%{http_code}" -X DELETE "$BASE_URL$endpoint" 2>/dev/null)
    status_code=$(echo "$response" | tail -n1)
    
    if [[ "$status_code" == "$expected_status" || "$status_code" == "400" || "$status_code" == "403" ]]; then
        # Accept 400/403 as valid responses for DELETE endpoints (auth/validation)
        echo -e "${GREEN}✓ $status_code${NC}"
        ((SUCCESS_COUNT++))
    else
        echo -e "${RED}✗ $status_code (expected $expected_status or 4xx)${NC}"
    fi
}

echo -e "${YELLOW}=== Root & Health Endpoints ===${NC}"
test_get "/" "Welcome message"
test_get "/health" "Application health check"
test_get "/health/push" "Health push for monitoring"

echo ""
echo -e "${YELLOW}=== Main API Endpoints ===${NC}"

# Conversation API
test_post "/api/v1/test" "Basic conversation test" '{"message": "Hello test"}'
test_post "/api/v1/conversation" "Main conversation endpoint" '{"message": "Hello", "context": {}}'

# GPS & Location API
test_get "/gps" "GPS map interface"
test_get "/api/v1/gps/coords" "GPS coordinates"
test_get "/api/v1/gps/location" "Current location"
test_get "/api/v1/gps/proximity" "Proximity data"
test_get "/api/v1/gps/home" "Home coordinates"
test_get "/api/v1/gps/history" "GPS history"
test_get "/api/v1/gps/cube_current_loc" "External cube location"
test_get "/api/v1/gps/landmarks" "Available landmarks"

# GIS Data API
test_get "/api/v1/gis/streets" "Street data"
test_get "/api/v1/gis/toilets" "Toilet locations"
test_get "/api/v1/gis/blocks" "City blocks"
test_get "/api/v1/gis/plazas" "Plaza locations"
test_get "/api/v1/gis/initial" "Initial map data"
test_get "/api/v1/gis/trash_fence" "Trash fence boundary"
test_get "/api/v1/gis/zones" "Zone boundaries"
test_delete "/api/v1/gis/cache" "Clear GIS cache"

# System API
test_get "/api/v1/system/health" "System health check"
test_post "/api/v1/system/restart" "System restart" '{"level": "soft", "auth_token": "test"}' "401"
test_post "/api/v1/system/clear_queues" "Clear queues" '{"auth_token": "test"}' "401"
test_get "/api/v1/system/restart_history" "Restart history"

# Entities API
test_post "/api/v1/entities/change_notification" "Entity change notification" '{"entity_id": "test.entity"}'
test_post "/api/v1/entities/refresh" "Entity refresh" '{}'
test_get "/api/v1/entities/list" "Entity list"
test_get "/api/v1/entities/light" "Light entities"
test_get "/api/v1/entities/sensor" "Sensor entities"

# Tools API
test_post "/api/v1/tool_test" "Tool test" '{"message": "Test tools"}'
test_post "/api/v1/home_assistant" "Home Assistant integration" '{"message": "Test HA"}'

# LLM API
test_post "/api/v1/llm/complete" "LLM completion" '{"prompt": "Hello"}'
test_get "/api/v1/llm/models" "Available models"

# Persona API
test_get "/api/v1/persona" "Current persona"
test_post "/api/v1/persona" "Set persona" '{"persona": "buddy"}'
test_get "/api/v1/personas" "Available personas"
test_post "/api/v1/persona/sync" "Persona sync" '{"direction": "from_ha"}'
test_delete "/api/v1/persona/state" "Clear persona state"

# Proactive API
test_post "/api/v1/proactive/attention" "Proactive attention" '{"level": "moderate"}'
test_post "/api/v1/proactive/mood" "Proactive mood" '{"mood": "happy"}'
test_post "/api/v1/proactive/custom" "Custom proactive" '{"prompt": "Test"}'
test_post "/api/v1/proactive/morning" "Morning greeting" '{}'
test_post "/api/v1/proactive/night" "Night lullaby" '{}'

# Context Generation API
test_post "/api/v1/context/generate" "Context generation" '{"prompt": "Test context"}'

# Deployment API
test_post "/api/v1/deploy/webhook" "GitHub webhook" '{"ref": "refs/heads/main"}' "400"
test_post "/api/v1/deploy/internal" "Internal deployment" '{}' "401"
test_post "/api/v1/deploy/manual" "Manual deployment" '{}' "401"
test_get "/api/v1/deploy/status" "Deployment status"

echo ""
echo -e "${YELLOW}=== Admin Endpoints ===${NC}"

# Main Admin
test_get "/admin" "Admin interface"
test_get "/admin/conversations/test-session" "Admin conversation view"
test_get "/admin/errors" "Admin errors page"
test_post "/admin/test_tts" "Admin TTS test" '{"message": "Test"}'
test_post "/admin/test_character" "Admin character test" '{"character": "buddy"}'
test_post "/admin/proactive_conversation" "Admin proactive conversation" '{"character": "buddy"}'
test_get "/admin/status" "Admin status"
test_post "/admin/extract_memories" "Extract memories" '{}'
test_get "/admin/session_history?session_id=test" "Session history"
test_get "/admin/memories" "Admin memories"
test_get "/admin/api/conversations" "Admin conversations API"
test_get "/admin/tools" "Admin tools interface"
test_get "/admin/logs" "Admin logs interface"
test_get "/admin/api/logs" "Admin logs API"
test_get "/admin/api/tools" "Admin tools API"
test_get "/admin/api/tools/methods" "Admin tool methods"
test_get "/admin/api/tools/openai-functions" "Admin OpenAI functions"
test_get "/admin/api/conversations/test-session" "Admin conversation API"
test_get "/admin/landmarks" "Admin landmarks" "403"
test_post "/admin/spoof_gps" "GPS spoofing" '{"latitude": 40.7, "longitude": -119.2}' "403"
test_delete "/admin/spoof_gps" "Clear GPS spoofing" "403"
test_get "/admin/current_location" "Admin current location"

# Admin Scenarios
test_get "/admin/scenarios" "Admin scenarios interface"
test_post "/admin/scenarios/compare" "Scenario comparison" '{"scenario_id": "first_contact", "models": ["test"]}'
test_get "/admin/scenarios/first_contact" "Scenario details"
test_post "/admin/scenarios/custom" "Custom scenario" '{"name": "Test", "messages": []}'

# Admin Benchmarks
test_get "/admin/benchmarks" "Admin benchmarks interface"
test_get "/admin/benchmarks/history" "Benchmark history"
test_post "/admin/benchmarks/compare" "Benchmark comparison" '{"models": "test1,test2"}' "400"

echo ""
echo -e "${YELLOW}=== Development Endpoints (if enabled) ===${NC}"

# Development Analytics (only available in development/test)
test_get "/api/v1/logs/errors" "Error statistics" "404"
test_get "/api/v1/logs/circuit_breakers" "Circuit breaker status" "404"
test_post "/api/v1/logs/circuit_breakers/reset" "Reset circuit breakers" "404"
test_get "/api/v1/analytics/conversations" "Conversation analytics" "404"
test_get "/api/v1/system_prompt" "System prompt preview" "404"
test_get "/api/v1/system_prompt/buddy" "Character system prompt" "404"
test_get "/api/v1/analytics/modules/test" "Module analytics" "404"
test_get "/api/v1/context/documents" "Context documents" "404"
test_post "/api/v1/context/documents" "Add context document" '{"filename": "test", "content": "test"}' "404"
test_post "/api/v1/context/search" "Search context" '{"query": "test"}' "404"

echo ""
echo -e "${YELLOW}=== Deploy Endpoints ===${NC}"

test_get "/deploy/health" "Deploy health check"
test_post "/deploy/trigger" "Deploy trigger" '{}' "401"

echo ""
echo -e "${BLUE}===========================================${NC}"
echo -e "${BLUE}  Test Results Summary${NC}"
echo -e "${BLUE}===========================================${NC}"
echo -e "Total endpoints tested: ${TOTAL_COUNT}"
echo -e "Successful responses: ${SUCCESS_COUNT}"
echo -e "Failed responses: $((TOTAL_COUNT - SUCCESS_COUNT))"

if [[ $SUCCESS_COUNT -eq $TOTAL_COUNT ]]; then
    echo -e "${GREEN}🎉 All endpoints responded correctly!${NC}"
    exit 0
else
    FAILURE_RATE=$(( (TOTAL_COUNT - SUCCESS_COUNT) * 100 / TOTAL_COUNT ))
    echo -e "${YELLOW}⚠️  $FAILURE_RATE% of endpoints had unexpected responses${NC}"
    echo -e "${YELLOW}Note: Some failures may be expected (auth required, dev-only endpoints, etc.)${NC}"
    exit 1
fi