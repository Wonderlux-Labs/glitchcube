# frozen_string_literal: true

namespace :host do
  # Host system configuration
  SINATRA_PATH = Dir.pwd
  SINATRA_PORT = ENV['PORT'] || '4567'
  
  desc 'Deploy Sinatra app on host system (pull from git and restart)'
  task :deploy do
    puts '🚀 Deploying Sinatra application on host...'
    
    # Check for uncommitted changes
    if system('git diff-index --quiet HEAD --')
      puts '✅ No uncommitted changes'
    else
      puts '⚠️  Warning: You have uncommitted changes'
      print 'Continue anyway? [y/N]: '
      response = $stdin.gets.chomp.downcase
      exit 1 unless response == 'y'
    end
    
    # Pull latest from git
    puts '📥 Pulling latest from GitHub...'
    current_branch = `git branch --show-current`.strip
    
    if system("git pull origin #{current_branch}")
      puts "✅ Updated to latest #{current_branch}"
    else
      puts '❌ Git pull failed!'
      exit 1
    end
    
    # Bundle install if Gemfile changed
    if `git diff HEAD@{1} --name-only`.include?('Gemfile')
      puts '📦 Gemfile changed, running bundle install...'
      system('bundle install')
    end
    
    # Run migrations if needed
    if `git diff HEAD@{1} --name-only`.include?('db/migrate')
      puts '🗄️ Running database migrations...'
      system('bundle exec rake db:migrate')
    end
    
    # Restart Sinatra
    Rake::Task['host:restart'].invoke
    
    puts '🎉 Host deployment complete!'
  end
  
  desc 'Restart Sinatra application'
  task :restart do
    puts '🔄 Restarting Sinatra application...'
    
    # Try different restart methods
    if File.exist?('tmp/pids/puma.pid')
      # Puma with pid file
      pid = File.read('tmp/pids/puma.pid').to_i
      puts "  Stopping Puma (PID: #{pid})..."
      Process.kill('TERM', pid) rescue nil
      sleep 2
      system('bundle exec puma -C config/puma.rb -d')
      puts '✅ Puma restarted'
      
    elsif system('pgrep -f "ruby.*app.rb" > /dev/null 2>&1')
      # Direct ruby process
      puts '  Stopping Sinatra process...'
      system('pkill -f "ruby.*app.rb"')
      sleep 2
      system("bundle exec ruby app.rb -p #{SINATRA_PORT} > log/sinatra.log 2>&1 &")
      puts '✅ Sinatra restarted'
      
    else
      puts '⚠️  No running Sinatra process found'
      puts '  Starting new instance...'
      system("bundle exec ruby app.rb -p #{SINATRA_PORT} > log/sinatra.log 2>&1 &")
      puts '✅ Sinatra started'
    end
    
    # Verify it's running
    sleep 2
    if system("curl -s http://localhost:#{SINATRA_PORT}/health > /dev/null 2>&1")
      puts "✅ Sinatra responding on port #{SINATRA_PORT}"
    else
      puts '⚠️  Sinatra may not be running properly'
      puts '  Check logs: tail -f log/sinatra.log'
    end
  end
  
  desc 'Check Sinatra application status'
  task :status do
    puts '🔍 Checking Sinatra application status...'
    
    # Check if process is running
    if system('pgrep -f "ruby.*app.rb" > /dev/null 2>&1')
      pid = `pgrep -f "ruby.*app.rb"`.strip
      puts "✅ Sinatra is running (PID: #{pid})"
    else
      puts '❌ Sinatra is not running'
    end
    
    # Check health endpoint
    if system("curl -s http://localhost:#{SINATRA_PORT}/health > /dev/null 2>&1")
      puts "✅ Health check passed on port #{SINATRA_PORT}"
      
      # Get detailed health info
      health_response = `curl -s http://localhost:#{SINATRA_PORT}/health 2>/dev/null`
      puts "  Response: #{health_response}"
    else
      puts "❌ Health check failed on port #{SINATRA_PORT}"
    end
    
    # Check git status
    branch = `git branch --show-current`.strip
    commit = `git rev-parse --short HEAD`.strip
    puts "📦 Git: #{branch} @ #{commit}"
    
    # Check for updates
    system('git fetch origin > /dev/null 2>&1')
    behind = `git rev-list HEAD..origin/#{branch} --count`.strip.to_i
    if behind > 0
      puts "⚠️  #{behind} commits behind origin/#{branch}"
      puts '  Run "rake host:deploy" to update'
    else
      puts '✅ Up to date with origin'
    end
  end
  
  desc 'View Sinatra application logs'
  task :logs do
    log_file = 'log/sinatra.log'
    if File.exist?(log_file)
      system("tail -f #{log_file}")
    else
      puts "❌ Log file not found: #{log_file}"
      puts '  Sinatra might be logging to stdout/stderr'
      puts '  Try: journalctl -f -u sinatra (if using systemd)'
    end
  end
  
  desc 'Run Sinatra in development mode (foreground)'
  task :dev do
    puts '🔧 Starting Sinatra in development mode...'
    puts 'Press Ctrl+C to stop'
    
    ENV['RACK_ENV'] = 'development'
    system("bundle exec ruby app.rb -p #{SINATRA_PORT}")
  end
end

# Full deployment task that does everything
namespace :deploy do
  desc 'Full deployment: Pull git, restart Sinatra, deploy HA config'
  task full: ['host:deploy', 'hass:deploy'] do
    puts '✨ Full deployment complete!'
    puts '  Host: Updated and restarted'
    puts '  Home Assistant: Config deployed'
  end
  
  desc 'Check if deployment is needed'
  task :check do
    puts '🔍 Checking for updates...'
    
    # Check git
    system('git fetch origin > /dev/null 2>&1')
    branch = `git branch --show-current`.strip
    behind = `git rev-list HEAD..origin/#{branch} --count`.strip.to_i
    
    if behind > 0
      puts "📦 #{behind} new commits available"
      
      # Show what changed
      puts "\nChanges in new commits:"
      changes = `git log HEAD..origin/#{branch} --oneline`
      puts changes.lines.take(5).join
      puts '...' if changes.lines.count > 5
      
      # Check what type of files changed
      files_changed = `git diff HEAD..origin/#{branch} --name-only`
      
      needs_host = files_changed.match?(/\.(rb|yml|gemfile)/i)
      needs_hass = files_changed.include?('config/homeassistant')
      
      puts "\n📋 Deployment needed for:"
      puts "  - Sinatra host" if needs_host
      puts "  - Home Assistant" if needs_hass
      
      if needs_host && needs_hass
        puts "\n💡 Run: rake deploy:full"
      elsif needs_host
        puts "\n💡 Run: rake host:deploy"
      elsif needs_hass
        puts "\n💡 Run: rake hass:deploy"
      end
    else
      puts '✅ Everything is up to date!'
    end
  end
  
  desc 'Deploy based on what changed'
  task :smart do
    puts '🤖 Smart deployment based on changes...'
    
    # Fetch and analyze
    system('git fetch origin > /dev/null 2>&1')
    branch = `git branch --show-current`.strip
    
    files_changed = `git diff HEAD..origin/#{branch} --name-only 2>/dev/null`
    
    if files_changed.empty?
      puts '✅ No changes to deploy'
      exit 0
    end
    
    needs_host = files_changed.match?(/\.(rb|yml|gemfile)/i)
    needs_hass = files_changed.include?('config/homeassistant')
    
    if needs_host
      puts '📦 Deploying Sinatra changes...'
      Rake::Task['host:deploy'].invoke
    end
    
    if needs_hass
      puts '🏠 Deploying Home Assistant changes...'
      Rake::Task['hass:deploy'].invoke
    end
    
    puts '✅ Smart deployment complete!'
  end
end

# Convenience aliases
desc 'Deploy everything'
task deploy: 'deploy:full'

desc 'Check deployment status'
task status: ['host:status', 'hass:status']