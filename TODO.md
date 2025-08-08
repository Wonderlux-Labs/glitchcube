# Glitch Cube TODO

## Current Development Focus

### Phase 2: Tool Execution Cleanup
- [ ] Remove tool execution fallback mechanisms from ConversationModule
- [ ] Standardize on LLM tool calling approach via ToolExecutor
- [ ] Clean up dual execution paths in hardware operations

### Phase 3: Webhook Simplification
- [ ] Remove bidirectional webhook complexity from HA integration
- [ ] Consolidate remaining conversation endpoints
- [ ] Document simplified webhook flow

### Phase 4: Final Cleanup
- [ ] Remove deprecated methods from codebase
- [ ] Clean up unused dependencies
- [ ] Update all documentation to reflect final architecture

## Testing & Quality

### Test Suite Health
- **Total Tests**: 655 examples
- **Current Failures**: ~67 (needs recount after recent fixes)
- **Line Coverage**: ~41%

### Priority Test Fixes
1. Redis connection issues in test environment
2. VCR cassette updates for new API patterns
3. Integration test coverage for conversation flow

## Feature Development

### Memory System Enhancement
- [ ] Add contextual memory triggers
- [ ] Implement memory decay/reinforcement
- [ ] Create memory visualization for admin panel

### Hardware Expression
- [ ] Coordinate TTS with LED patterns
- [ ] Implement mood-based lighting
- [ ] Add attention-getting behaviors

### Proactive Interactions
- [ ] Motion-triggered greetings
- [ ] Time-based personality shifts
- [ ] Environmental response patterns

## Operational Tasks

### Deployment & Monitoring
- [ ] Set up automated deployment pipeline
- [ ] Configure Uptime Kuma alerts
- [ ] Add performance monitoring

### Documentation
- [x] Reorganize documentation structure
- [x] Remove outdated docs
- [x] Create clear TOC
- [ ] Add API documentation
- [ ] Create operator manual

## Known Issues

### Minor
- RuboCop configuration needs update (plugins vs require)
- Some VCR cassettes need re-recording
- Warning about private method in entities.rb

### To Investigate
- Memory leak potential in long-running conversations
- Circuit breaker reset timing optimization
- TTS queue management during rapid interactions

---
*Last updated: January 2025*
*Focus: Simplifying architecture and improving test coverage*