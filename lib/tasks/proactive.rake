# frozen_string_literal: true

namespace :proactive do
  desc "Test attention-seeking behavior"
  task :attention, [:level] => :environment do |_t, args|
    level = args[:level] || 'moderate'
    puts "🎭 Triggering attention-seeking behavior (#{level})..."
    
    result = Services::ProactiveInteractionService.seek_attention(loneliness_level: level)
    
    if result[:success]
      puts "✅ Proactive interaction complete!"
      puts "Response: #{result[:response]}"
    else
      puts "❌ Failed: #{result[:error]}"
    end
  end
  
  desc "Express a mood"
  task :mood, [:mood, :reason] => :environment do |_t, args|
    mood = args[:mood] || 'happy'
    reason = args[:reason]
    
    puts "😊 Expressing mood: #{mood}"
    result = Services::ProactiveInteractionService.express_mood(mood, reason)
    
    if result[:success]
      puts "✅ Mood expressed!"
    else
      puts "❌ Failed: #{result[:error]}"
    end
  end
  
  desc "Morning greeting"
  task :morning => :environment do
    puts "☀️ Good morning!"
    Services::ProactiveInteractionService.morning_greeting
  end
  
  desc "Nighttime lullaby"
  task :night => :environment do
    puts "🌙 Good night!"
    Services::ProactiveInteractionService.nighttime_lullaby
  end
  
  desc "Custom proactive prompt"
  task :custom, [:prompt] => :environment do |_t, args|
    prompt = args[:prompt] || "Express yourself creatively using speech and lights!"
    
    puts "🎨 Custom proactive interaction..."
    result = Services::ProactiveInteractionService.call(prompt: prompt)
    
    if result[:success]
      puts "✅ Complete!"
      puts "Response: #{result[:response]}"
    else
      puts "❌ Failed: #{result[:error]}"
    end
  end
end