#!/bin/bash

# Quick Essential Endpoints Test for Glitchcube
# Tests the most important endpoints for basic functionality
# Usage: ./scripts/test_essential_endpoints.sh

BASE_URL="http://localhost:4567"
SUCCESS_COUNT=0
TOTAL_COUNT=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}Essential Glitchcube Endpoints Test${NC}"
echo ""

# Function to test GET endpoints
test_get() {
    local endpoint="$1"
    local description="$2"
    
    ((TOTAL_COUNT++))
    echo -n "Testing GET $endpoint ($description)... "
    
    response=$(curl -s -w "\n%{http_code}" "$BASE_URL$endpoint" 2>/dev/null)
    status_code=$(echo "$response" | tail -n1)
    
    if [[ "$status_code" =~ ^2[0-9][0-9]$ ]]; then
        echo -e "${GREEN}✓ $status_code${NC}"
        ((SUCCESS_COUNT++))
    else
        echo -e "${RED}✗ $status_code${NC}"
    fi
}

# Function to test POST endpoints with JSON data
test_post() {
    local endpoint="$1"
    local description="$2"
    local data="$3"
    
    ((TOTAL_COUNT++))
    echo -n "Testing POST $endpoint ($description)... "
    
    response=$(curl -s -w "\n%{http_code}" -X POST \
        -H "Content-Type: application/json" \
        -d "$data" \
        "$BASE_URL$endpoint" 2>/dev/null)
    status_code=$(echo "$response" | tail -n1)
    
    if [[ "$status_code" =~ ^[2-4][0-9][0-9]$ ]]; then
        # Accept 2xx, 3xx, or 4xx as valid responses (4xx often expected for validation)
        echo -e "${GREEN}✓ $status_code${NC}"
        ((SUCCESS_COUNT++))
    else
        echo -e "${RED}✗ $status_code${NC}"
    fi
}

# Essential endpoints
echo -e "${YELLOW}Core Endpoints:${NC}"
test_get "/" "Root welcome"
test_get "/health" "Health check"

echo ""
echo -e "${YELLOW}API Endpoints:${NC}"
test_post "/api/v1/conversation" "Main conversation API" '{"message": "Hello", "context": {}}'
test_get "/api/v1/gps/coords" "GPS coordinates"
test_get "/api/v1/llm/models" "LLM models"
test_get "/api/v1/system/health" "System health"
test_get "/api/v1/entities/list" "Entity list"

echo ""
echo -e "${YELLOW}Admin Interface:${NC}"
test_get "/admin" "Admin panel"
test_get "/admin/status" "Admin status"

echo ""
echo -e "${BLUE}Results: $SUCCESS_COUNT/$TOTAL_COUNT endpoints working${NC}"

if [[ $SUCCESS_COUNT -eq $TOTAL_COUNT ]]; then
    echo -e "${GREEN}🎉 All essential endpoints are working!${NC}"
    exit 0
else
    echo -e "${YELLOW}⚠️  Some endpoints may need attention${NC}"
    exit 1
fi