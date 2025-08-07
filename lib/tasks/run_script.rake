# frozen_string_literal: true

desc 'Run a script with full app environment loaded'
task :run_script, [:script_path] do |_task, args|
  # Load the app environment manually
  require_relative '../../config/initializers/config'
  script_path = args[:script_path]
  
  unless script_path
    puts "Usage: bundle exec rake run_script[path/to/script.rb]"
    puts "Example: bundle exec rake run_script[scripts/test_conversation_feedback.rb]"
    exit 1
  end
  
  script_full_path = File.expand_path(script_path)
  
  unless File.exist?(script_full_path)
    puts "❌ Script not found: #{script_full_path}"
    exit 1
  end
  
  puts "🚀 Running script: #{script_path}"
  puts "📁 Full path: #{script_full_path}"
  puts "🌍 Environment: #{GlitchCube.config.app.environment}"
  puts "=" * 50
  
  # Load and execute the script with full environment
  load script_full_path
end