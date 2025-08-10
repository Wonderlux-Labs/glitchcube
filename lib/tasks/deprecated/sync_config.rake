# frozen_string_literal: true

namespace :config do
  REMOTE_HOST = 'root@glitch.local'
  REMOTE_CONFIG_PATH = '/config'
  LOCAL_CONFIG_PATH = 'config/homeassistant'

  desc 'Create a backup of remote configuration'
  task :backup do
    puts '💾 Creating backup of remote configuration...'

    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    backup_name = "config_backup_#{timestamp}"

    # Create backup on remote
    puts '  📦 Creating archive on remote...'
    system("ssh #{REMOTE_HOST} 'cd /config && tar -czf /tmp/#{backup_name}.tar.gz --exclude=backups --exclude=home-assistant.log* --exclude=*.db* --exclude=.storage . && mkdir -p /config/backups && mv /tmp/#{backup_name}.tar.gz /config/backups/'")

    # Download backup to local
    puts '  📥 Downloading backup...'
    FileUtils.mkdir_p('backups')
    system("scp #{REMOTE_HOST}:/config/backups/#{backup_name}.tar.gz backups/")

    puts "✅ Backup created: backups/#{backup_name}.tar.gz"
    puts "🔧 Restore with: tar -xzf backups/#{backup_name}.tar.gz -C config/homeassistant/"
  end

  desc 'Diff local and remote configuration'
  task :diff do
    puts '🔍 Comparing local vs remote configuration...'

    # Create temp directory for remote files
    temp_dir = "/tmp/glitchcube_remote_#{Time.now.to_i}"
    FileUtils.mkdir_p(temp_dir)

    begin
      # Download key files for comparison
      key_files = ['configuration.yaml', 'automations.yaml', 'mqtt.yaml']

      key_files.each do |file|
        puts "  📄 Downloading #{file} for comparison..."
        system("scp -q #{REMOTE_HOST}:/config/#{file} #{temp_dir}/ 2>/dev/null")

        # Compare each file
        local_file = "#{LOCAL_CONFIG_PATH}/#{file}"
        remote_file = "#{temp_dir}/#{file}"

        if File.exist?(local_file) && File.exist?(remote_file)
          puts "\n📊 Comparing #{file}:"
          diff_output = `diff -u #{local_file} #{remote_file} 2>/dev/null`
          if diff_output.empty?
            puts '  ✅ Files are identical'
          else
            puts '  📝 Differences found:'
            puts diff_output.lines.first(10).join # Show first 10 lines of diff
            puts '  ... (truncated)' if diff_output.lines.count > 10
          end
        else
          puts "\n⚠️  #{file}: Missing locally or remotely"
        end
      end
    ensure
      # Cleanup temp directory
      FileUtils.rm_rf(temp_dir)
    end
  end

  desc 'Sync configuration (rsync-style with deletions)'
  task :sync do
    puts '🔄 Syncing configuration files with glitch.local (with deletions)...'

    # Ensure local directory exists
    FileUtils.mkdir_p(LOCAL_CONFIG_PATH)

    # Use rsync for proper sync with deletions
    rsync_cmd = [
      'rsync', '-av', '--delete', '--exclude=*.log*', '--exclude=*.db*',
      '--exclude=.storage/', '--exclude=backups/', '--exclude=tts/',
      '--exclude=.cloud/', '--exclude=deps/', '--exclude=.DS_Store',
      "#{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/",
      "#{LOCAL_CONFIG_PATH}/"
    ].join(' ')

    puts "  📡 Running: #{rsync_cmd}"
    if system(rsync_cmd)
      puts '✅ Configuration sync completed!'
    else
      puts '❌ Sync failed!'
      exit 1
    end
  end

  desc 'Watch for local changes and auto-sync'
  task :watch do
    puts '👀 Watching for local configuration changes...'
    puts 'Press Ctrl+C to stop'

    require 'listen'

    listener = Listen.to(LOCAL_CONFIG_PATH, only: /\.(yaml|yml)$/) do |modified, added, removed|
      changes = []
      changes.concat(modified.map { |f| "Modified: #{f}" })
      changes.concat(added.map { |f| "Added: #{f}" })
      changes.concat(removed.map { |f| "Removed: #{f}" })

      if changes.any?
        puts "\n📝 Changes detected:"
        changes.each { |change| puts "  #{change}" }

        print '🔄 Auto-sync to remote? [Y/n]: '
        response = $stdin.gets.chomp.downcase

        Rake::Task['config:push'].execute if response.empty? || response == 'y' || response == 'yes'
      end
    end

    listener.start
    sleep
  end
end
