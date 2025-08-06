# frozen_string_literal: true

# Display self-healing mode on startup
module SelfHealingBanner
  def self.display
    mode = GlitchCube.config.self_healing_mode

    puts "\n#{'=' * 80}"
    puts '🧬 SELF-HEALING ERROR HANDLER'.center(80)
    puts '=' * 80

    case mode
    when 'OFF'
      puts '  Mode: OFF (Disabled)'.center(80)
      puts '  Status: No autonomous error fixing'.center(80)
    when 'DRY_RUN'
      puts '  Mode: DRY_RUN (Analysis Only)'.center(80)
      puts '  Status: Analyzing errors and logging proposed fixes'.center(80)
      puts '  Storage: log/proposed_fixes/YYYYMMDD_proposed_fixes.jsonl'.center(80)
      puts '  Review: ./review_proposed_fixes.rb'.center(80)
    when 'YOLO'
      puts '  ⚠️  Mode: YOLO (AUTONOMOUS DEPLOYMENT) ⚠️'.center(80)
      puts '  Status: WILL MODIFY CODE AND DEPLOY AUTOMATICALLY!'.center(80)
      puts "  Confidence: #{GlitchCube.config.self_healing_min_confidence}".center(80)
      puts "  Threshold: #{GlitchCube.config.self_healing_error_threshold} occurrences".center(80)
      puts
      puts '  🚨 WARNING: Code will be modified and pushed to git! 🚨'.center(80)
    else
      puts "  Mode: UNKNOWN (#{mode})".center(80)
      puts '  Defaulting to OFF'.center(80)
    end

    puts '=' * 80
    puts
  end
end

# Display banner on app startup (not in test environment)
SelfHealingBanner.display unless GlitchCube.config.test?
