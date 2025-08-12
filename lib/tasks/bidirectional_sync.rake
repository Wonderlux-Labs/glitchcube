# frozen_string_literal: true

namespace :config do
  REMOTE_HOST = 'root@glitch.local'
  REMOTE_CONFIG_PATH = '/config'
  LOCAL_CONFIG_PATH = 'config/homeassistant'
  desc 'Bidirectional sync - pull newer remote files, then push newer local files'
  task :bisync do
    puts '🔄 Performing bidirectional sync with glitch.local...'

    # Common exclude patterns
    excludes = [
      '--exclude=.storage', '--exclude=backups', '--exclude=tts',
      '--exclude=.cloud', '--exclude=deps', '--exclude=llmvision',
      '--exclude=home-assistant.log*', '--exclude=*.db*',
      '--exclude=secrets.yaml', '--exclude=.DS_Store',
      '--exclude=**/__pycache__/', '--exclude=*.pyc',
      '--exclude=logs/', '--exclude=*.log'
    ].join(' ')

    # Include patterns for YAML and our custom component
    includes = [
      '--include=*/',
      '--include=*.yaml', '--include=*.yml',
      '--include=**/*.yaml', '--include=**/*.yml',
      '--include=packages/',
      '--include=packages/**',
      '--include=custom_components/glitchcube_conversation/',
      '--include=custom_components/glitchcube_conversation/**',
      '--exclude=custom_components/**',
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

    # Load exclusion patterns
    sync_excludes_file = "#{LOCAL_CONFIG_PATH}/.sync_excludes"
    exclude_patterns = []
    if File.exist?(sync_excludes_file)
      exclude_patterns = File.readlines(sync_excludes_file).map(&:strip).reject(&:empty?).reject { |l| l.start_with?('#') }
      puts "  📋 Loaded #{exclude_patterns.length} exclusion patterns"
    end

    # Common exclude/include patterns for rsync
    excludes = [
      '--exclude=.storage', '--exclude=backups', '--exclude=tts',
      '--exclude=.cloud', '--exclude=deps', '--exclude=llmvision',
      '--exclude=home-assistant.log*', '--exclude=*.db*',
      '--exclude=secrets.yaml', '--exclude=.DS_Store',
      '--exclude=**/__pycache__/', '--exclude=*.pyc',
      '--exclude=logs/', '--exclude=*.log'
    ] + exclude_patterns.map { |p| "--exclude=#{p}" }

    includes = [
      '--include=**/',
      '--include=*.yaml', '--include=*.yml',
      '--include=**/*.yaml', '--include=**/*.yml',
      '--include=packages/',
      '--include=packages/**',
      '--include=custom_components/glitchcube_conversation/',
      '--include=custom_components/glitchcube_conversation/**',
      '--exclude=custom_components/**',
      '--exclude=*'
    ]

    all_patterns = (excludes + includes).join(' ')

    # Simple approach: Check what rsync would do in both directions
    puts '  🔍 Analyzing changes...'

    # Check what would be pulled from remote (including deletions)
    # NOTE: Don't use --update in dry-run to see ALL differences for conflict detection
    pull_dry_run = "rsync -avn --delete #{all_patterns} #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/ #{LOCAL_CONFIG_PATH}/"
    pull_output = `#{pull_dry_run} 2>&1`

    # Check what would be pushed to remote (including deletions)
    # NOTE: Don't use --update in dry-run to see ALL differences for conflict detection
    push_dry_run = "rsync -avn --delete #{all_patterns} #{LOCAL_CONFIG_PATH}/ #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/"
    push_output = `#{push_dry_run} 2>&1`

    # Parse results
    pull_changes = pull_output.lines.grep(/^[<>cf]/).map { |l| l.split.last }.compact
    push_changes = push_output.lines.grep(/^[<>cf]/).map { |l| l.split.last }.compact

    # Parse deletions separately
    pull_deletions = pull_output.lines.grep(/^deleting/).map { |l| l.sub(/^deleting /, '').strip }
    push_deletions = push_output.lines.grep(/^deleting/).map { |l| l.sub(/^deleting /, '').strip }

    # Report what would happen
    has_changes = pull_changes.any? || push_changes.any? || pull_deletions.any? || push_deletions.any?

    if has_changes
      puts '  📊 Sync Analysis Results:'

      if pull_changes.any?
        puts '    📥 Would pull from remote:'
        pull_changes.each { |f| puts "      ← #{f}" }
      end

      if push_changes.any?
        puts '    📤 Would push to remote:'
        push_changes.each { |f| puts "      → #{f}" }
      end

      if pull_deletions.any?
        puts '    🗑️  Would delete locally (remote deleted):'
        pull_deletions.each { |f| puts "      ✗ #{f}" }
      end

      if push_deletions.any?
        puts '    🗑️  Would delete on remote (local deleted):'
        push_deletions.each { |f| puts "      ✗ #{f}" }
      end

      # Check for conflicts (same file in both directions)
      conflicts = pull_changes & push_changes
      if conflicts.any?
        puts '    ⚠️  CONFLICTS (modified in both locations):'
        conflicts.each { |f| puts "      ⚡ #{f}" }

        puts '  ❓ How to resolve conflicts?'
        puts '    1) Keep local changes (push to remote)'
        puts '    2) Keep remote changes (pull from remote)'
        puts '    3) Manual review (abort)'
        print '  Choice [1/2/3]: '

        choice = $stdin.gets.chomp
        case choice
        when '1'
          puts '  📤 Keeping local - will push changes'
          # Just do push sync with deletions
          push_cmd = "rsync -av --delete #{all_patterns} #{LOCAL_CONFIG_PATH}/ #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/"
          system(push_cmd)
        when '2'
          puts '  📥 Keeping remote - will pull changes'
          # Just do pull sync with deletions
          pull_cmd = "rsync -av --delete #{all_patterns} #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/ #{LOCAL_CONFIG_PATH}/"
          system(pull_cmd)
        else
          puts '  ❌ Sync cancelled for manual review'
          exit 0
        end
      else
        print '  Continue with bidirectional sync? [Y/n]: '
        response = $stdin.gets.chomp.downcase
        unless response.empty? || response == 'y' || response == 'yes'
          puts '❌ Sync cancelled'
          exit 0
        end

        # No conflicts, do bidirectional sync with deletions
        puts '  🔄 Performing bidirectional sync with deletions...'

        # Pull with deletions first
        pull_cmd = "rsync -av --update --delete #{all_patterns} #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/ #{LOCAL_CONFIG_PATH}/"
        puts '  ⬇️  Pulling with deletions...'
        system(pull_cmd)

        # Then push with deletions
        push_cmd = "rsync -av --update --delete #{all_patterns} #{LOCAL_CONFIG_PATH}/ #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/"
        puts '  ⬆️  Pushing with deletions...'
        system(push_cmd)
      end
    else
      puts '  ✅ No changes detected - files are in sync!'
    end

    puts '✅ Smart sync completed!'
  end
end

# Convenience aliases
task 'bisync' => 'config:bisync'
task 'smartsync' => 'config:smartsync'
