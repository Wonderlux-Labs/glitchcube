# SimpleLogger Migration Implementation Notes

## What We Built

Created `lib/services/simple_logger.rb` - a clean, minimal logging system based on your design:

- **Single log format**: `[timestamp] [LEVEL] message #tag1 #tag2 (caller) key=value`
- **Structured tags**: Easy filtering with `#conversation #error #performance`
- **Environment-driven**: `LOG_LEVEL` and `LOG_TO_SCREEN` env vars
- **Operational focus**: System health, not conversation content
- **File + screen**: Writes to `logs/current.log`, echoes to screen if enabled
- **Error handling**: Stack traces with `log_error()` method
- **Screen debugging**: `SimpleLogger.puts()` for temporary debug output

## Current State

**✅ Complete:**
- SimpleLogger service implemented
- Configuration added to `.env.example` 
- Logger initializer updated to use SimpleLogger
- **Partially migrated**: `conversation_module.rb` - replaced 8 puts statements with structured logging

**🚧 In Progress:**
- Started replacing puts statements in `lib/services/llm_service.rb`
- Found 191 files with puts statements throughout codebase

**⏳ Pending:**
- Replace remaining puts statements (massive scope)
- Replace all UnifiedLoggerService calls 
- Remove old UnifiedLoggerService (377 lines)
- Test the complete migration

## Discovery - Current Logging Complexity

**UnifiedLoggerService** (377 lines):
- Complex JSON metadata system
- Thread-local context management  
- Multiple specialized logging methods (`api_call`, `conversation`, `home_assistant`, etc.)
- Custom formatters and emoji systems
- File rotation and directory management

**Puts statements everywhere** (191 files):
- Debug output scattered across entire codebase
- Mix of conditional `if GlitchCube.config.debug?` checks
- Testing scripts, rake tasks, services, tools, routes
- No consistent format or structure

## Migration Strategy

### Phase 1: Core Services (High Impact)
```ruby
# Replace in order:
lib/modules/conversation_module.rb ✅ (done)  
lib/services/llm_service.rb 🚧 (in progress)
lib/services/tool_executor.rb
lib/services/conversation_tool_handler.rb 
lib/services/error_handling_llm.rb
lib/routes/api/conversation.rb
```

### Phase 2: UnifiedLoggerService Calls
```ruby
# Find and replace patterns:
Services::UnifiedLoggerService.info() → Services::SimpleLogger.info()
Services::UnifiedLoggerService.api_call() → Services::SimpleLogger.info() with tags
Services::UnifiedLoggerService.error() → Services::SimpleLogger.error()
log.debug() → Services::SimpleLogger.debug()
```

### Phase 3: Mass Puts Replacement
**Strategy**: Focus on production code first, leave test/script files for last

**High Priority**:
- `lib/` directory (services, modules, tools)
- `app.rb` main application
- `lib/routes/` API endpoints

**Low Priority**:
- `scripts/testing_scripts/` (62 files)
- `spec/` test files  
- Rake tasks and utilities

### Phase 4: Configuration & Cleanup
- Remove UnifiedLoggerService files
- Update requires throughout codebase
- Add LOG_LEVEL/LOG_TO_SCREEN to production configs
- Run full test suite

## Example Migration Patterns

### Debug Puts → Structured Logging
```ruby
# Before:
puts "🔧 Auto-loaded #{tools.size} tools for persona '#{persona}'" if debug?

# After:  
Services::SimpleLogger.debug("Auto-loaded tools for persona", 
  tagged: [:tools], persona: persona, count: tools.size)
```

### Error Puts → Error Logging
```ruby
# Before:
puts "ERROR: #{e.message}" 
puts e.backtrace.first(5)

# After:
Services::SimpleLogger.log_error(error: e, message: "Operation failed", 
  tagged: [:api, :failure], operation: "user_action")
```

### Complex UnifiedLogger → Simple Tags
```ruby  
# Before:
Services::UnifiedLoggerService.api_call(
  service: 'openrouter', endpoint: '/chat', status: 200, duration: 450
)

# After:
Services::SimpleLogger.info("API call completed", 
  tagged: [:api], service: 'openrouter', duration_ms: 450, success: true)
```

## Benefits After Migration

1. **Grep-friendly logs**: `grep "#performance" logs/current.log`
2. **Unified format**: All logs follow same structure  
3. **Operational focus**: System health over conversation content
4. **Simple debugging**: Screen-only puts for development
5. **Zero dependencies**: No complex JSON parsing or formatters
6. **Lean codebase**: Remove 377 lines of logging complexity

## Rollback Plan

If issues arise:
1. Keep old UnifiedLoggerService until migration proven
2. Update logger initializer to switch back
3. Git revert individual file changes as needed
4. All existing functionality preserved during transition

## Estimated Effort

- **High priority files**: ~2-3 hours focused work
- **Mass puts replacement**: ~4-6 hours (scripting + verification)  
- **Testing & cleanup**: ~1-2 hours
- **Total**: ~8-12 hours for complete migration

Ready to resume when you give the signal! 🚀