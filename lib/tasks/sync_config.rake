# frozen_string_literal: true

namespace :config do
  REMOTE_HOST = 'root@glitch.local'
  REMOTE_CONFIG_PATH = '/config'
  LOCAL_CONFIG_PATH = 'config/homeassistant'

  desc 'Pull all Home Assistant configuration files from glitch.local'
  task :pull do
    puts "📥 Pulling configuration files from #{REMOTE_HOST}..."

    # Ensure local directory exists
    FileUtils.mkdir_p(LOCAL_CONFIG_PATH)

    # Sync main configuration files
    sync_files = [
      'configuration.yaml',
      'automations.yaml',
      'scenes.yaml',
      'scripts.yaml',
      'rest_commands.yaml'
    ]

    # Sync directories
    sync_dirs = [
      'automations/',
      'scripts/',
      'sensors/',
      'template/',
      'binary_sensors/',
      'input_helpers/',
      'themes/',
      'dashboard',
      'custom_components/glitchcube_conversation/'
    ]

    # Pull individual files
    sync_files.each do |file|
      puts "  📄 Pulling #{file}..."
      system("scp -q #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/#{file} #{LOCAL_CONFIG_PATH}/ 2>/dev/null || echo '    ⚠️  #{file} not found on remote'")
    end

    # Pull directories
    sync_dirs.each do |dir|
      puts "  📁 Pulling #{dir}..."
      FileUtils.mkdir_p("#{LOCAL_CONFIG_PATH}/#{dir}")
      system("scp -q -r #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/#{dir}* #{LOCAL_CONFIG_PATH}/#{dir} 2>/dev/null || echo '    ⚠️  #{dir} not found on remote'")
    end

    puts '✅ Configuration pull completed!'
    puts "🔍 Run 'rake config:status' to see what was pulled"
  end

  desc 'Push all Home Assistant configuration files to glitch.local'
  task :push do
    puts "📤 Pushing configuration files to #{REMOTE_HOST}..."

    unless Dir.exist?(LOCAL_CONFIG_PATH)
      puts "❌ Local config directory not found: #{LOCAL_CONFIG_PATH}"
      exit 1
    end

    # Backup remote config first
    puts '  💾 Creating backup on remote...'
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    system("ssh #{REMOTE_HOST} 'mkdir -p /config/backups && tar -czf /config/backups/config_backup_#{timestamp}.tar.gz -C /config --exclude=backups --exclude=\"home-assistant.log*\" --exclude=\"*.db*\" . 2>/dev/null || echo \"Backup creation failed\"'")

    # Push main configuration files
    sync_files = [
      'configuration.yaml',
      'automations.yaml',
      'scenes.yaml',
      'scripts.yaml',
      'rest_commands.yaml'
    ]

    # Push directories
    sync_dirs = [
      'automations/',
      'scripts/',
      'sensors/',
      'template/',
      'binary_sensors/',
      'input_helpers/',
      'themes/',
      'custom_components/glitchcube_conversation/'
    ]

    # Push individual files
    sync_files.each do |file|
      local_file = "#{LOCAL_CONFIG_PATH}/#{file}"
      if File.exist?(local_file)
        puts "  📄 Pushing #{file}..."
        system("scp -q #{local_file} #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/")
      else
        puts "    ⚠️  #{file} not found locally, skipping"
      end
    end

    # Push directories
    sync_dirs.each do |dir|
      local_dir = "#{LOCAL_CONFIG_PATH}/#{dir}"
      if Dir.exist?(local_dir) && !Dir.empty?(local_dir)
        puts "  📁 Pushing #{dir}..."
        # Create directory on remote first
        system("ssh #{REMOTE_HOST} 'mkdir -p #{REMOTE_CONFIG_PATH}/#{dir}'")
        # Push all files in directory
        system("scp -q -r #{local_dir}* #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/#{dir}")
      else
        puts "    ⚠️  #{dir} not found locally or empty, skipping"
      end
    end

    puts '✅ Configuration push completed!'
    puts '🔄 Reloading all Home Assistant YAML configurations...'

    # Use the new reload_all service that reloads everything at once
    system("ssh #{REMOTE_HOST} 'ha core restart' 2>/dev/null")

    puts '✅ All YAML configurations reloaded!'
    puts "💡 Note: All configuration changes, including those to configuration.yaml and custom_components, are now applied automatically by restarting Home Assistant core."
  end

  desc 'Show status of local vs remote configuration'
  task :status do
    puts '📊 Configuration Status Report'
    puts '=' * 50

    # Check if local config exists
    if Dir.exist?(LOCAL_CONFIG_PATH)
      local_files = Dir.glob("#{LOCAL_CONFIG_PATH}/**/*").select { |f| File.file?(f) }
      puts "📁 Local config files: #{local_files.count}"

      # Show recent changes
      puts "\n📝 Recently modified local files:"
      local_files.sort_by { |f| File.mtime(f) }.reverse.first(5).each do |file|
        rel_path = file.sub("#{LOCAL_CONFIG_PATH}/", '')
        mtime = File.mtime(file).strftime('%Y-%m-%d %H:%M:%S')
        puts "  #{mtime} - #{rel_path}"
      end
    else
      puts '❌ No local configuration directory found'
      puts "💡 Run 'rake config:pull' to download configuration from remote"
    end

    # Check remote connectivity
    puts "\n🌐 Remote connectivity:"
    if system("ssh -q #{REMOTE_HOST} 'exit' 2>/dev/null")
      puts "  ✅ Can connect to #{REMOTE_HOST}"

      # Check Home Assistant status
      ha_status = `ssh #{REMOTE_HOST} 'ha core info --raw-json 2>/dev/null | jq -r .state 2>/dev/null || echo "unknown"'`.strip
      puts "  🏠 Home Assistant status: #{ha_status}"
    else
      puts "  ❌ Cannot connect to #{REMOTE_HOST}"
    end
  end

  desc 'Validate local configuration files'
  task :validate do
    puts '🔍 Validating local configuration...'

    unless Dir.exist?(LOCAL_CONFIG_PATH)
      puts '❌ Local config directory not found'
      exit 1
    end

    config_file = "#{LOCAL_CONFIG_PATH}/configuration.yaml"
    unless File.exist?(config_file)
      puts '❌ configuration.yaml not found'
      exit 1
    end

    # Basic YAML syntax check
    require 'yaml'
    begin
      YAML.load_file(config_file)
      puts '✅ configuration.yaml syntax is valid'
    rescue Psych::SyntaxError => e
      puts '❌ YAML syntax error in configuration.yaml:'
      puts "   #{e.message}"
      exit 1
    end

    # Check for common issues
    content = File.read(config_file)

    issues = []
    issues << 'logbook.log service found (deprecated)' if content.include?('logbook.log')
    issues << 'Missing recorder configuration' unless content.include?('recorder:')
    issues << 'Missing mqtt configuration' unless content.include?('mqtt:')

    if issues.any?
      puts '⚠️  Potential issues found:'
      issues.each { |issue| puts "   - #{issue}" }
    else
      puts '✅ No obvious issues found in configuration'
    end
  end

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

# Aliases for convenience
task 'pull' => 'config:pull'
task 'push' => 'config:push'
task 'sync:pull' => 'config:pull'
task 'sync:push' => 'config:push'
