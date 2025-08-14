#!/bin/bash
# Simple Starlink gRPC status check script
# Usage: ./starlink_grpc_check.sh

STARLINK_HOST="${STARLINK_HOST:-192.168.100.1}"
STARLINK_PORT="${STARLINK_PORT:-9200}"
TIMEOUT="${TIMEOUT:-10}"

echo "Checking Starlink gRPC status at ${STARLINK_HOST}:${STARLINK_PORT}..."

# Try to get status using grpcurl (if available)
if command -v grpcurl >/dev/null 2>&1; then
    echo "Using grpcurl to query Starlink..."
    grpcurl -plaintext -max-time ${TIMEOUT} \
        -d '{}' \
        ${STARLINK_HOST}:${STARLINK_PORT} \
        SpaceX.API.Device.Device/Handle | \
        jq '.dishGetStatus | {
            state: .state,
            uptime_s: .deviceState.uptimeS,
            downlink_throughput_bps: .downlinkThroughputBps,
            uplink_throughput_bps: .uplinkThroughputBps,
            snr: .snr,
            pop_ping_latency_ms: .popPingLatencyMs,
            downlink_mb_per_min: (.downlinkThroughputBps * 60 / 8 / 1000000),
            uplink_mb_per_min: (.uplinkThroughputBps * 60 / 8 / 1000000),
            total_mb_per_min: ((.downlinkThroughputBps + .uplinkThroughputBps) * 60 / 8 / 1000000)
        }'
else
    echo "grpcurl not found. Install with:"
    echo "  # On Ubuntu/Debian:"
    echo "  sudo apt-get install grpcurl"
    echo "  # On macOS:"
    echo "  brew install grpcurl"
    echo "  # Manual install:"
    echo "  wget https://github.com/fullstorydev/grpcurl/releases/download/v1.8.7/grpcurl_1.8.7_linux_x86_64.tar.gz"
    
    # Fallback: try to ping the gRPC port
    if timeout ${TIMEOUT} nc -z ${STARLINK_HOST} ${STARLINK_PORT} >/dev/null 2>&1; then
        echo "✓ Starlink gRPC port ${STARLINK_PORT} is reachable"
    else
        echo "✗ Cannot reach Starlink gRPC port ${STARLINK_PORT}"
        exit 1
    fi
fi