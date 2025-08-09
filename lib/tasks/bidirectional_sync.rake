# frozen_string_literal: true

namespace :config do
  desc 'Bidirectional sync - pull newer remote files, then push newer local files'
  task :bisync do
    puts '🔄 Performing bidirectional sync with glitch.local...'
    
    REMOTE_HOST = 'root@glitch.local'
    REMOTE_CONFIG_PATH = '/config'
    LOCAL_CONFIG_PATH = 'config/homeassistant'
    
    # Common exclude patterns
    excludes = [
      '--exclude=.storage', '--exclude=backups', '--exclude=tts',
      '--exclude=.cloud', '--exclude=deps', '--exclude=llmvision',
      '--exclude=home-assistant.log*', '--exclude=*.db*',
      '--exclude=secrets.yaml', '--exclude=.DS_Store',
      '--exclude=**/__pycache__/', '--exclude=*.pyc'
    ].join(' ')
    
    # Include patterns for YAML and our custom component
    includes = [
      '--include=*/', '--include=*.yaml', '--include=*.yml',
      '--include=custom_components/', '--include=custom_components/glitchcube_conversation/',
      '--include=custom_components/glitchcube_conversation/**',
      '--exclude=custom_components/*',
      '--exclude=*'
    ].join(' ')
    
    # Step 1: Pull newer files from remote
    puts '  ⬇️  Pulling newer files from remote...'
    pull_cmd = "rsync -av --update #{excludes} #{includes} #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/ #{LOCAL_CONFIG_PATH}/"
    
    unless system(pull_cmd)
      puts '❌ Pull sync failed!'
      exit 1
    end
    
    # Step 2: Push newer files to remote
    puts '  ⬆️  Pushing newer files to remote...'
    push_cmd = "rsync -av --update #{excludes} #{includes} #{LOCAL_CONFIG_PATH}/ #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/"
    
    unless system(push_cmd)
      puts '❌ Push sync failed!'
      exit 1
    end
    
    puts '✅ Bidirectional sync completed!'
    puts '💡 Files are now synchronized based on modification time'
    puts '   - Newer remote files were pulled'
    puts '   - Newer local files were pushed'
  end
  
  desc 'Smart sync - bidirectional sync with conflict detection'
  task :smartsync do
    puts '🧠 Smart sync with conflict detection...'
    
    REMOTE_HOST = 'root@glitch.local'
    REMOTE_CONFIG_PATH = '/config'
    LOCAL_CONFIG_PATH = 'config/homeassistant'
    
    # First, do a dry run to see what would change
    puts '  🔍 Analyzing changes...'
    
    dry_run_cmd = [
      'rsync', '-avn', '--update',
      '--exclude=.storage', '--exclude=backups', '--exclude=tts',
      '--exclude=.cloud', '--exclude=deps', '--exclude=llmvision',
      '--exclude=home-assistant.log*', '--exclude=*.db*',
      '--exclude=secrets.yaml', '--exclude=.DS_Store',
      '--exclude=**/__pycache__/', '--exclude=*.pyc',
      '--include=*/', '--include=*.yaml', '--include=*.yml',
      '--include=custom_components/', '--include=custom_components/glitchcube_conversation/',
      '--include=custom_components/glitchcube_conversation/**',
      '--exclude=custom_components/*',
      '--exclude=*',
      "#{LOCAL_CONFIG_PATH}/",
      "#{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/"
    ].join(' ')
    
    output = `#{dry_run_cmd} 2>&1`
    
    if output.include?('would')
      puts '  📝 The following changes would be made:'
      output.lines.select { |l| l.include?('would') }.each { |l| puts "     #{l.strip}" }
      
      print '  Continue with sync? [Y/n]: '
      response = $stdin.gets.chomp.downcase
      
      unless response.empty? || response == 'y' || response == 'yes'
        puts '❌ Sync cancelled'
        exit 0
      end
    end
    
    # Perform the actual bidirectional sync
    Rake::Task['config:bisync'].execute
  end
end

# Convenience aliases
task 'bisync' => 'config:bisync'
task 'smartsync' => 'config:smartsync'