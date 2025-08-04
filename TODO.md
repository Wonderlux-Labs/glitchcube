# Glitch Cube TODO

## Critical Missing Tests (High Priority)

### 1. Configuration System Tests
- [ ] Test `GlitchCube::Config.validate!` method
- [ ] Test required vs optional environment variables
- [ ] Test production configuration validation
- [ ] Test `redis_connection` and `persistence_enabled?` helpers
- [ ] Test configuration errors in different environments

### 2. Infrastructure Components (0% Coverage)
- [ ] **BeaconService** tests - critical for gallery monitoring
  - [ ] Test heartbeat sending
  - [ ] Test alert sending
  - [ ] Test error handling and retries
- [ ] **BeaconHeartbeatJob** tests - essential for 24/7 operations
  - [ ] Test successful heartbeat job execution
  - [ ] Test job failure scenarios
  - [ ] Test job result storage
- [ ] **BeaconAlertJob** tests
  - [ ] Test alert job execution
  - [ ] Test different alert levels
- [ ] Redis connection failure/recovery scenarios
- [ ] Sidekiq queue processing error handling

### 3. Art Installation Scenarios
- [ ] Power loss/restart recovery testing
- [ ] Network connectivity interruption during conversations
- [ ] Resource exhaustion on Raspberry Pi (memory/CPU/storage)
- [ ] Multiple concurrent visitors/conversations
- [ ] Temperature monitoring for 24/7 operation
- [ ] SD card wear considerations

### 4. System Integration
- [ ] End-to-end flow with all services (HA + AI + Background jobs)
- [ ] Graceful degradation when services are unavailable
- [ ] Long-running conversation memory management
- [ ] Docker environment-specific behaviors

## High Priority Tests

### Error Recovery & Resilience
- [ ] Test what happens when Redis/Sidekiq goes down
- [ ] Test OpenRouter API failures and fallbacks
- [ ] Test Home Assistant becomes unavailable mid-conversation
- [ ] Test database connection failures
- [ ] Test disk space exhaustion scenarios

### Performance & Load Testing
- [ ] Test handling multiple concurrent conversations
- [ ] Test memory usage under load
- [ ] Test conversation cleanup and memory management
- [ ] Test Raspberry Pi resource constraints

### Missing Service Tests
- [ ] **ContextRetrievalService** unit tests (has integration tests)
- [ ] **ConversationSummarizer** unit tests (has integration tests)
- [ ] **SystemPromptService** edge case coverage

## Medium Priority Tests

### Network & Connectivity
- [ ] Test offline/poor connectivity scenarios
- [ ] Test network interruption during API calls
- [ ] Test timeout handling for external services

### Configuration & Environment
- [ ] Test environment variable validation
- [ ] Test different RACK_ENV configurations
- [ ] Test Docker-specific scenarios
- [ ] Test required vs optional config validation

### Integration Scenarios
- [ ] Test multi-user simultaneous conversations
- [ ] Test conversation context switching
- [ ] Test service dependency chains

## Low Priority Tests

### Docker & Deployment
- [ ] Test Docker environment-specific behaviors
- [ ] Test container health checks
- [ ] Test volume mounting in different environments

### Monitoring & Alerting
- [ ] Test health endpoint monitoring
- [ ] Test log aggregation
- [ ] Test disk space monitoring
- [ ] Test temperature monitoring alerts

### Optimization
- [ ] Test image cleanup processes
- [ ] Test log rotation effectiveness
- [ ] Test backup/restore procedures

## Test Infrastructure Improvements

### Current Strengths
- ✅ Excellent VCR setup for API testing
- ✅ Good separation of unit vs integration tests
- ✅ Proper mock/stub usage for external services
- ✅ Clean test data management and cleanup
- ✅ SimpleCov for coverage tracking

### Areas for Enhancement
- [ ] Add performance benchmarking
- [ ] Add memory usage tracking in tests
- [ ] Add flaky test detection
- [ ] Add test parallelization for faster CI

## Notes

**Priority Focus**: Infrastructure components (BeaconService, Configuration validation) are critical for deployment safety and 24/7 gallery operation.

**Art Installation Context**: Tests should consider the unique requirements of an autonomous art installation running 24/7 in gallery environments with potential power issues, network instability, and resource constraints.