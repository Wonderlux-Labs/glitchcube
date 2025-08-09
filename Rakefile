# frozen_string_literal: true

require 'rspec/core/rake_task'
require 'sinatra/activerecord/rake'

# Load custom rake tasks
Dir[File.join(__dir__, 'lib/tasks/*.rake')].each { |f| load f }

# Load the app for database tasks
namespace :db do
  task :load_config do
    # Load database config first for consistent configuration
    require_relative 'config/database_config'
    configure_database!
    require './app'
  end
end

RSpec::Core::RakeTask.new(:spec)

task default: :spec

desc 'Run the application'
task :run do
  exec 'bundle exec ruby app.rb'
end

desc 'Start Sidekiq'
task :sidekiq do
  exec 'bundle exec sidekiq'
end

desc 'Console with application loaded'
task :console do
  exec 'bin/console'
end

desc 'Console (alternate method using IRB)'
task :c do
  require 'irb'
  require './app'

  # Load all lib files
  Dir[File.join(__dir__, 'lib/**/*.rb')].each { |f| require f }

  # Start IRB
  ARGV.clear
  IRB.start
end

desc 'Show all routes'
task :routes do
  require_relative 'app'

  puts "\n🎲 Glitch Cube Routes"
  puts '===================='

  routes = []

  # Helper to check if a route renders a view
  def check_for_view(file, line)
    return nil unless file && File.exist?(file)

    # Read a few lines around the route handler
    lines = File.readlines(file)
    start_line = [line - 1, 0].max
    end_line = [line + 20, lines.length].min

    # Look for erb/haml/slim render calls in the handler
    handler_code = lines[start_line...end_line].join

    case handler_code
    when /erb\s*[(:]\s*[:'](\w+)/
      return "erb: #{Regexp.last_match(1)}"
    when /haml\s*[(:]\s*[:'](\w+)/
      return "haml: #{Regexp.last_match(1)}"
    when /slim\s*[(:]\s*[:'](\w+)/
      return "slim: #{Regexp.last_match(1)}"
    when /render\s+['"]([^'"]+)['"]/
      return "render: #{Regexp.last_match(1)}"
    end

    nil
  end

  # Get routes from the main app
  GlitchCubeApp.routes.each do |method, method_routes|
    method_routes.each do |route|
      pattern = route[0]
      # Route structure: [pattern, keys, conditions, block]
      block = route[3]

      # Clean up the pattern
      path = pattern.to_s
      path = path.gsub(/^\(\?-mix:/, '') # Remove regex prefix
      path = path.gsub(/\)$/, '')          # Remove closing paren
      path = path.gsub(/\$$/, '')          # Remove end anchor
      path = path.gsub('^', '') # Remove start anchor
      path = path.gsub('\\', '') # Remove escape chars

      handler_info = 'inline'
      view_info = nil

      if block&.source_location
        file, line = block.source_location
        handler_info = "#{file}:#{line}"
        view_info = check_for_view(file, line)
      end

      routes << {
        method: method.upcase,
        path: path.empty? ? '/' : path,
        handler: handler_info,
        view: view_info
      }
    end
  end

  # Sort routes by path then method
  routes.sort_by! { |r| [r[:path], r[:method]] }

  # Calculate column widths
  method_width = routes.map { |r| r[:method].length }.max + 2
  path_width = routes.map { |r| r[:path].length }.max + 2
  handler_width = routes.map { |r| r[:handler].length }.max + 2

  # Print header
  puts "\n#{' METHOD'.ljust(method_width)} #{'PATH'.ljust(path_width)} #{'HANDLER'.ljust(handler_width)} VIEW"
  puts '-' * (method_width + path_width + handler_width + 20)

  # Print routes
  routes.each do |route|
    line = "#{route[:method].ljust(method_width)} #{route[:path].ljust(path_width)} #{route[:handler].ljust(handler_width)}"
    line += " 📄 #{route[:view]}" if route[:view]
    puts line
  end

  puts "\nTotal routes: #{routes.size}"
  puts "Routes with views: #{routes.count { |r| r[:view] }}"
end

# Docker tasks removed - no longer using Docker deployment

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

    # Show process status (update based on current deployment method)
    puts "\nService Status:"
    puts "TODO: Add service status check for current deployment"
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
  desc 'Push to production - commits local changes, pushes to GitHub, deploys to Mac Mini'
  task :push, [:message] do |_t, args|
    unless args[:message]
      puts '❌ Error: Commit message required'
      puts 'Usage: rake deploy:push["Your commit message"]'
      puts 'Flow: Local → GitHub → Mac Mini (via SSH)'
      exit 1
    end

    sh "./scripts/push-to-production.sh \"#{args[:message]}\""
  end

  desc 'Quick push to production with timestamp message'
  task :quick do
    timestamp = Time.now.strftime('%Y-%m-%d %H:%M')
    sh "./scripts/push-to-production.sh \"Deploy at #{timestamp}\""
  end

  desc 'Manual pull from GitHub (run on Mac Mini)'
  task :pull do
    puts '📥 Manually pulling and deploying from GitHub...'
    sh './scripts/pull-from-github.sh'
  end

  desc 'Check for updates (run on Mac Mini)'
  task :check do
    puts '🔍 Checking for updates from GitHub...'
    sh './scripts/check-for-updates.sh' do |ok, res|
      # Don't fail if exit code is 1 (no updates)
      puts 'No updates available.' if !ok && res.exitstatus == 1
    end
  end
end
