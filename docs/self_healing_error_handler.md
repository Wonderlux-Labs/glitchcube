# 🧬 Self-Healing Error Handler (EXPERIMENTAL)

## Overview

An autonomous error handling system that analyzes recurring errors, proposes fixes using AI, and optionally deploys them automatically. Designed for the Glitch Cube art installation to maintain itself during multi-day events.

## Key Features

### 🛡️ Dry-Run Mode (DEFAULT)
- **Analyzes errors without modifying code**
- Saves proposed fixes for human review
- Marks errors as "analyzed" to prevent re-processing
- Logs all proposals with confidence scores

### 🤖 Smart Analysis
- Only acts on recurring errors (configurable threshold)
- AI assesses criticality and confidence
- Uses specialized debug agents for root cause analysis
- Generates targeted, minimal fixes

### 📊 Review & Monitoring
- Review script shows proposed fixes by confidence level
- Tracks most common errors and patterns
- JSON/CSV export for deeper analysis
- 7-day retention of proposed fixes

## Configuration

```bash
# .env settings
ENABLE_SELF_HEALING=true           # Master switch
SELF_HEALING_DRY_RUN=true          # Safe mode - only propose, don't apply
SELF_HEALING_MIN_CONFIDENCE=0.85   # Minimum AI confidence to propose fix
SELF_HEALING_ERROR_THRESHOLD=3     # Errors must occur 3+ times
```

## Usage

### 1. Enable in Development

```bash
# .env
ENABLE_SELF_HEALING=true
SELF_HEALING_DRY_RUN=true  # Start with dry-run!
```

### 2. Integrate with Services

```ruby
class YourService
  include ErrorHandlerIntegration
  
  def risky_method
    # your code
  rescue => e
    with_error_healing do
      # fallback behavior
    end
    raise # re-raise after handling
  end
end
```

### 3. Monitor Proposed Fixes

```bash
# Review all proposed fixes
./review_proposed_fixes.rb

# Filter by confidence
./review_proposed_fixes.rb --confidence 0.9

# Export as JSON for analysis
./review_proposed_fixes.rb --format json > fixes.json

# Show last 2 days only
./review_proposed_fixes.rb --days 2
```

### 4. Review Output Example

```
📋 PROPOSED FIXES SUMMARY
================================================================================

✅ HIGH CONFIDENCE (3 fixes)

  2025-01-06 - StandardError
    Error: Connection refused
    Service: TTSService | Method: speak
    Occurrences: 5 | Confidence: 0.92
    Fix: Add retry logic with exponential backoff
    Files: lib/services/tts_service.rb

⚠️  MEDIUM CONFIDENCE (2 fixes)

  2025-01-06 - NoMethodError
    Error: undefined method 'speak' for nil
    Service: ConversationModule | Method: respond
    Occurrences: 3 | Confidence: 0.78
    Fix: Add nil check before method call
    Files: lib/modules/conversation_module.rb

STATISTICS:
  Total fixes proposed: 5
  Critical issues: 2
  Average confidence: 0.85
```

## How It Works

### Error Flow

1. **Error Occurs** → Tracked in Redis with unique signature
2. **Threshold Met** → After N occurrences, triggers analysis
3. **AI Assessment** → Determines criticality and confidence
4. **Fix Generation** → Debug agent analyzes code and proposes fix
5. **Dry-Run Save** → Stores proposal and marks error as "analyzed"
6. **Human Review** → Use review script to see all proposals

### Data Storage

**With Database:**
- Saves to `proposed_fixes` table
- Full ActiveRecord model with status tracking
- Can approve/reject/apply fixes programmatically

**Without Database:**
- Falls back to `log/proposed_fixes/YYYYMMDD_proposed_fixes.jsonl`
- One JSON object per line for easy parsing
- Review script works with both storage methods

## Safety Features

- ✅ **Dry-run by default** - Must explicitly disable to apply fixes
- ✅ **High confidence required** - 85% default threshold
- ✅ **Recurring errors only** - Single errors ignored
- ✅ **Development only** - Production flag blocks activation
- ✅ **7-day memory** - Won't re-analyze same errors
- ✅ **Rollback tracking** - Can revert deployed fixes

## Testing

```bash
# Run all tests (20 examples, 100% passing)
bundle exec rspec spec/services/error_handling_llm*

# Test the system safely
./test_self_healing.rb

# Check Redis for tracking
redis-cli keys 'glitchcube:error_count:*'
redis-cli keys 'glitchcube:fixed_errors:*'
```

## Switching to Live Mode (DANGEROUS!)

If you're feeling brave and want actual deployments:

```bash
# .env
SELF_HEALING_DRY_RUN=false  # ⚠️ WILL MODIFY AND DEPLOY CODE!
```

Features in live mode:
- Commits fixes to git
- Pushes to main branch
- Tracks commit SHAs for rollback
- Can revert with: `Services::ErrorHandlingLLM.new.rollback_last_fix`

## Architecture

```
ErrorHandlerIntegration (Mixin)
    ↓
Services::ErrorHandlingLLM
    ├── assess_criticality() → AI evaluates error
    ├── analyze_and_fix_code() → Debug agent creates fix
    ├── save_proposed_fix() → Stores for review (dry-run)
    └── apply_and_deploy_fix() → Git commit/push (live mode)
```

## Future Enhancements

- Web UI for reviewing proposed fixes
- Confidence learning from accepted/rejected fixes
- Pattern recognition for similar errors
- Automated testing of proposed fixes
- Slack/Discord notifications for critical errors

## Important Notes

This is **highly experimental** and designed for an art installation that needs to self-maintain. While it has safety features, autonomous code modification is inherently risky. Always start with dry-run mode and carefully review proposed fixes before enabling live mode.

The system is designed to be conservative - it will only act on recurring, critical errors with high confidence. Most errors will be logged but not fixed, which is the safe default.