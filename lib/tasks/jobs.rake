# frozen_string_literal: true

namespace :jobs do
  desc "Run summarizer and memory jobs manually"
  task :run, [:job_name] do |_task, args|
    # Load the application
    require_relative '../../app'
    job_name = args[:job_name]
    
    if job_name.nil? || job_name.empty?
      puts "ERROR run with job name"
      exit
    end

    puts "🤖 Running #{job_name} manually..."
    puts "=" * 50
    
    case job_name
    when 'memory_consolidation'
      run_memory_consolidation
    when 'personality_memory'
      run_personality_memory
    when 'personal_summarizer'
      run_personal_summarizer
    when 'interaction_summarizer'
      run_interaction_summarizer
    when 'event_memory_summarizer'
      run_event_memory_summarizer
    when 'daily_summary'
      run_daily_summary
    else
      puts "❌ Unknown job: #{job_name}"
      puts "Run 'rake jobs:run' to see available jobs"
      exit 1
    end
  end

  desc "Schedule all background jobs to start in 10 seconds (for startup)"
  task :schedule_startup do
    # Load the application
    require_relative '../../app'
    return unless defined?(Sidekiq) && Sidekiq.redis_info
    
    puts "📅 Scheduling background jobs to start in 10 seconds..."
    
    jobs_to_schedule = [
      { name: 'memory_consolidation', class: Jobs::MemoryConsolidationJob, delay: 10 },
      { name: 'personality_memory', class: Jobs::PersonalityMemoryJob, delay: 15 },
      { name: 'personal_summarizer', class: Jobs::PersonalSummarizerJob, delay: 20 },
      { name: 'interaction_summarizer', class: Jobs::InteractionSummarizerJob, delay: 25 },
      { name: 'event_memory_summarizer', class: Jobs::EventMemorySummarizerJob, delay: 30 }
    ]
    
    jobs_to_schedule.each do |job_info|
      begin
        job_info[:class].perform_in(job_info[:delay])
        puts "✅ Scheduled #{job_info[:name]} in #{job_info[:delay]} seconds"
      rescue StandardError => e
        puts "❌ Failed to schedule #{job_info[:name]}: #{e.message}"
      end
    end
    
    puts "🚀 All jobs scheduled for startup!"
  end

  private

  def run_memory_consolidation
    puts "🧠 Running Memory Consolidation Job..."
    start_time = Time.now
    
    begin
      job = Jobs::MemoryConsolidationJob.new
      result = job.perform
      
      duration = ((Time.now - start_time) * 1000).round
      puts "✅ Memory consolidation completed in #{duration}ms"
      puts "Result: #{result}" if result
    rescue StandardError => e
      puts "❌ Memory consolidation failed: #{e.message}"
      puts e.backtrace.first(3).join("\n")
    end
  end

  def run_personality_memory
    puts "🎭 Running Personality Memory Job..."
    start_time = Time.now
    
    begin
      job = Jobs::PersonalityMemoryJob.new
      result = job.perform
      
      duration = ((Time.now - start_time) * 1000).round
      puts "✅ Personality memory extraction completed in #{duration}ms"
      puts "Result: #{result}" if result
    rescue StandardError => e
      puts "❌ Personality memory extraction failed: #{e.message}"
      puts e.backtrace.first(3).join("\n")
    end
  end

  def run_personal_summarizer
    puts "🤔 Running Personal Summarizer Job..."
    start_time = Time.now
    
    begin
      job = Jobs::PersonalSummarizerJob.new
      result = job.perform
      
      duration = ((Time.now - start_time) * 1000).round
      puts "✅ Personal summarization completed in #{duration}ms"
      puts "Result: #{result}" if result
    rescue StandardError => e
      puts "❌ Personal summarization failed: #{e.message}"
      puts e.backtrace.first(3).join("\n")
    end
  end

  def run_interaction_summarizer
    puts "👥 Running Interaction Summarizer Job..."
    start_time = Time.now
    
    begin
      job = Jobs::InteractionSummarizerJob.new
      result = job.perform
      
      duration = ((Time.now - start_time) * 1000).round
      puts "✅ Interaction summarization completed in #{duration}ms"
      puts "Result: #{result}" if result
    rescue StandardError => e
      puts "❌ Interaction summarization failed: #{e.message}"
      puts e.backtrace.first(3).join("\n")
    end
  end

  def run_event_memory_summarizer
    puts "⭐ Running Event Memory Summarizer Job..."
    start_time = Time.now
    
    begin
      job = Jobs::EventMemorySummarizerJob.new
      result = job.perform
      
      duration = ((Time.now - start_time) * 1000).round
      puts "✅ Event memory summarization completed in #{duration}ms"
      puts "Result: #{result}" if result
    rescue StandardError => e
      puts "❌ Event memory summarization failed: #{e.message}"
      puts e.backtrace.first(3).join("\n")
    end
  end

  def run_daily_summary
    puts "📅 Running Daily Summary Job..."
    start_time = Time.now
    
    begin
      job = Jobs::DailySummaryJob.new
      result = job.perform
      
      duration = ((Time.now - start_time) * 1000).round
      puts "✅ Daily summarization completed in #{duration}ms"
      puts "Result: #{result}" if result
    rescue StandardError => e
      puts "❌ Daily summarization failed: #{e.message}"
      puts e.backtrace.first(3).join("\n")
    end
  end
end