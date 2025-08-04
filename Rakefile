# frozen_string_literal: true

require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

task default: :spec

desc 'Run the application'
task :run do
  exec 'bundle exec ruby app.rb'
end

desc 'Run the application with Puma'
task :puma do
  exec 'bundle exec puma -C config/puma.rb'
end

desc 'Start Sidekiq'
task :sidekiq do
  exec 'bundle exec sidekiq'
end

desc 'Console with application loaded'
task :console do
  exec 'bundle exec pry -r ./app.rb'
end

namespace :docker do
  desc 'Show service status'
  task :status do
    sh 'docker-compose ps'
  end

  desc 'View logs (optionally specify service: rake docker:logs[glitchcube])'
  task :logs, [:service] do |_t, args|
    if args[:service]
      sh "docker-compose logs -f #{args[:service]}"
    else
      sh 'docker-compose logs -f'
    end
  end

  desc 'Restart all services'
  task :restart do
    sh 'docker-compose restart'
  end

  desc 'Restart specific service (rake docker:restart_service[homeassistant])'
  task :restart_service, [:service] do |_t, args|
    sh "docker-compose restart #{args[:service]}"
  end

  desc 'Pull latest images and restart'
  task :update do
    sh 'docker-compose pull'
    sh 'docker-compose up -d'
  end
end

namespace :health do
  desc 'Check service health'
  task :check do
    puts '🎲 Glitch Cube Health Check'
    puts '=========================='

    # Check Glitch Cube API
    begin
      require 'net/http'
      response = Net::HTTP.get_response(URI('http://localhost:4567/health'))
      if response.code == '200'
        puts '✅ Glitch Cube API: Healthy'
      else
        puts "❌ Glitch Cube API: Unhealthy (#{response.code})"
      end
    rescue StandardError => e
      puts "❌ Glitch Cube API: Error (#{e.message})"
    end

    # Check Home Assistant
    begin
      response = Net::HTTP.get_response(URI('http://localhost:8123/api/'))
      if %w[200 401].include?(response.code)
        puts '✅ Home Assistant: Running'
      else
        puts "❌ Home Assistant: Unhealthy (#{response.code})"
      end
    rescue StandardError => e
      puts "❌ Home Assistant: Error (#{e.message})"
    end

    # Show Docker status
    puts "\nDocker Services:"
    sh 'docker-compose ps', verbose: false
  end
end

namespace :logs do
  desc 'Clean up old log files'
  task :cleanup do
    require 'fileutils'

    log_dir = 'logs'
    days_to_keep = 7

    puts "Cleaning up logs older than #{days_to_keep} days..."

    Dir.glob("#{log_dir}/**/*.log*").each do |file|
      if File.mtime(file) < Time.now - (days_to_keep * 24 * 60 * 60)
        puts "Removing: #{file}"
        FileUtils.rm(file)
      end
    end

    puts 'Log cleanup complete!'
  end
end

namespace :backup do
  desc 'Backup application data'
  task :create do
    timestamp = Time.now.strftime('%Y%m%d-%H%M%S')
    backup_file = "backup-#{timestamp}.tar.gz"

    puts "Creating backup: #{backup_file}"
    sh "tar -czf backups/#{backup_file} data/ logs/ .env"
    puts "✅ Backup created: backups/#{backup_file}"
  end

  desc 'List available backups'
  task :list do
    puts 'Available backups:'
    Dir.glob('backups/*.tar.gz').each do |backup|
      size = File.size(backup) / 1024.0 / 1024.0
      puts "  #{File.basename(backup)} (#{size.round(2)} MB)"
    end
  end
end

namespace :deploy do
  desc 'Push to production - commits local changes, pushes to GitHub, deploys to Raspberry Pi'
  task :push, [:message] do |_t, args|
    unless args[:message]
      puts '❌ Error: Commit message required'
      puts 'Usage: rake deploy:push["Your commit message"]'
      puts 'Flow: Local → GitHub → Raspberry Pi (via SSH)'
      exit 1
    end

    sh "./scripts/push-to-production.sh \"#{args[:message]}\""
  end

  desc 'Quick push to production with timestamp message'
  task :quick do
    timestamp = Time.now.strftime('%Y-%m-%d %H:%M')
    sh "./scripts/push-to-production.sh \"Deploy at #{timestamp}\""
  end

  desc 'Rollback to last known good deployment (run on Raspberry Pi)'
  task :rollback do
    puts '🔄 Rolling back to last known good deployment...'
    sh 'docker tag glitchcube:last-known-good glitchcube:latest'
    sh 'docker-compose up -d glitchcube sidekiq'
    puts '✅ Rollback complete!'
  end
  
  desc 'Manual pull from GitHub (run on Raspberry Pi)'
  task :pull do
    puts '📥 Manually pulling and deploying from GitHub...'
    sh './scripts/pull-from-github.sh'
  end
  
  desc 'Check for updates (run on Raspberry Pi)'
  task :check do
    puts '🔍 Checking for updates from GitHub...'
    sh './scripts/check-for-updates.sh' do |ok, res|
      # Don't fail if exit code is 1 (no updates)
      if !ok && res.exitstatus == 1
        puts 'No updates available.'
      end
    end
  end
end
