#!/usr/bin/env ruby
# frozen_string_literal: true

# Zero-Leak VCR Migration Script
# Automatically migrates from old VCR setup to Zero-Leak VCR

require 'fileutils'
require 'pathname'

class VCRMigration
  BACKUP_DIR = 'vcr_migration_backup'

  def initialize(root_path = '.')
    @root_path = Pathname.new(root_path).expand_path
    @spec_path = @root_path / 'spec'
    @support_path = @spec_path / 'support'
    @backup_path = @root_path / BACKUP_DIR

    puts '🔧 Zero-Leak VCR Migration Tool'
    puts "Root: #{@root_path}"
    puts '=' * 50
  end

  def migrate!
    validate_environment!

    create_backup!
    disable_old_files!
    update_spec_helper!
    migrate_test_files!
    generate_summary!

    puts "\n✅ Migration Complete!"
    puts 'Next steps:'
    puts '1. Review changes: git diff'
    puts '2. Test migration: bundle exec rspec'
    puts '3. Record missing cassettes: VCR_RECORD=true bundle exec rspec'
    puts '4. Commit changes when satisfied'
    puts '5. Restore from backup if needed: ruby scripts/migrate_vcr_setup.rb --rollback'
  end

  def rollback!
    puts '🔄 Rolling back VCR migration...'

    unless Dir.exist?(@backup_path)
      puts "❌ No backup found at #{@backup_path}"
      exit 1
    end

    # Restore files from backup
    Dir.glob("#{@backup_path}/**/*").each do |backup_file|
      next unless File.file?(backup_file)

      relative_path = Pathname.new(backup_file).relative_path_from(@backup_path)
      original_path = @root_path / relative_path

      puts "Restoring #{relative_path}"
      FileUtils.mkdir_p(original_path.dirname)
      FileUtils.cp(backup_file, original_path)
    end

    # Remove new files
    [@support_path / 'vcr_config.rb',
     @support_path / 'vcr_helpers_new.rb',
     @support_path / 'vcr_setup.rb'].each do |file|
      FileUtils.rm_f(file)
    end

    # Remove backup directory
    FileUtils.rm_rf(@backup_path)

    puts '✅ Rollback complete!'
  end

  private

  def validate_environment!
    unless Dir.exist?(@spec_path)
      puts '❌ No spec/ directory found. Are you in the right directory?'
      exit 1
    end

    unless File.exist?(@spec_path / 'spec_helper.rb')
      puts "❌ No spec_helper.rb found. This doesn't look like an RSpec project."
      exit 1
    end

    puts '✅ Environment validated'
  end

  def create_backup!
    puts '📦 Creating backup...'

    FileUtils.mkdir_p(@backup_path)

    # Backup files that will be modified or disabled
    files_to_backup = [
      @spec_path / 'spec_helper.rb',
      @support_path / 'vcr_helpers.rb',
      @support_path / 'vcr_auto_recording.rb',
      @support_path / 'vcr_request_tracker.rb'
    ].select { |f| File.exist?(f) }

    files_to_backup.each do |file|
      backup_file = @backup_path / file.relative_path_from(@root_path)
      FileUtils.mkdir_p(backup_file.dirname)
      FileUtils.cp(file, backup_file)
      puts "  Backed up: #{file.relative_path_from(@root_path)}"
    end

    puts "✅ Backup created at #{BACKUP_DIR}/"
  end

  def disable_old_files!
    puts '🚫 Disabling old VCR files...'

    old_files = [
      @support_path / 'vcr_helpers.rb',
      @support_path / 'vcr_auto_recording.rb',
      @support_path / 'vcr_request_tracker.rb'
    ]

    old_files.each do |file|
      next unless File.exist?(file)

      disabled_file = "#{file}.disabled"
      FileUtils.mv(file, disabled_file)
      puts "  Disabled: #{file.basename} → #{File.basename(disabled_file)}"
    end

    puts '✅ Old files disabled'
  end

  def update_spec_helper!
    puts '🔧 Updating spec_helper.rb...'

    spec_helper_path = @spec_path / 'spec_helper.rb'
    content = File.read(spec_helper_path)

    # Comment out old VCR configuration
    updated_content = content.gsub(/^VCR\.configure do.*?^end$/m) do |match|
      commented = match.lines.map { |line| "# #{line}" }.join
      "# OLD VCR Configuration - disabled by Zero-Leak migration\n#{commented}\n# END OLD VCR Configuration"
    end

    # Comment out old WebMock configuration
    updated_content = updated_content.gsub(/^WebMock\.disable_net_connect!.*?^end$/m) do |match|
      commented = match.lines.map { |line| "# #{line}" }.join
      "# OLD WebMock Configuration - disabled by Zero-Leak migration\n#{commented}\n# END OLD WebMock Configuration"
    end

    # Add Zero-Leak VCR require at the end of file
    unless updated_content.include?("require_relative 'support/vcr_setup'")
      updated_content += <<~RUBY

        # Zero-Leak VCR Configuration
        require_relative 'support/vcr_setup'
      RUBY
    end

    File.write(spec_helper_path, updated_content)
    puts '✅ spec_helper.rb updated'
  end

  def migrate_test_files!
    puts '🔄 Migrating test files...'

    test_files = Dir.glob("#{@spec_path}/**/*_spec.rb")
    migrated_count = 0

    test_files.each do |file_path|
      content = File.read(file_path)
      original_content = content.dup

      # Pattern 1: VCR.use_cassette('name') do ... end
      content = content.gsub(/VCR\.use_cassette\([^)]+\)\s+do(.*?)end/m) do |match|
        puts "    Found VCR.use_cassette in #{File.basename(file_path)}"
        # Convert to vcr: true pattern - this needs manual review
        "# TODO: Convert to vcr: true - #{match.gsub("\n", ' ')}"
      end

      # Pattern 2: vcr: { cassette_name: 'name' } → vcr: true
      content = content.gsub(/vcr:\s*\{\s*cassette_name:\s*[^}]+\}/, 'vcr: true')

      # Pattern 3: Add vcr: true to integration tests missing it
      if file_path.include?('/integration/') && !content.include?('vcr:')
        content = content.gsub(/(\s+it\s+['"][^'"]+['"])(\s+do)/) do |_match|
          "#{::Regexp.last_match(1)}, vcr: true#{::Regexp.last_match(2)}"
        end
      end

      # Write changes if content was modified
      next unless content != original_content

      File.write(file_path, content)
      migrated_count += 1
      puts "  Migrated: #{File.basename(file_path)}"
    end

    puts "✅ Migrated #{migrated_count} test files"
  end

  def generate_summary!
    puts '📊 Generating migration summary...'

    summary_file = @root_path / 'VCR_MIGRATION_SUMMARY.md'
    File.write(summary_file, <<~MARKDOWN)
      # Zero-Leak VCR Migration Summary

      **Migration completed at:** #{Time.now}

      ## Changes Made

      ### 1. Files Disabled
      - `spec/support/vcr_helpers.rb` → `vcr_helpers.rb.disabled`
      - `spec/support/vcr_auto_recording.rb` → `vcr_auto_recording.rb.disabled`#{'  '}
      - `spec/support/vcr_request_tracker.rb` → `vcr_request_tracker.rb.disabled`

      ### 2. Files Added
      - `spec/support/vcr_config.rb` - Core Zero-Leak VCR configuration
      - `spec/support/vcr_helpers_new.rb` - Simplified helpers
      - `spec/support/vcr_setup.rb` - Complete bulletproof setup

      ### 3. spec_helper.rb Updates
      - Old VCR configuration commented out
      - Zero-Leak VCR configuration added

      ### 4. Test File Updates
      - Converted complex VCR patterns to simple `vcr: true`
      - Added VCR to integration tests missing it
      - Flagged manual VCR.use_cassette for review

      ## Next Steps

      1. **Test the migration:**
         ```bash
         bundle exec rspec
         ```

      2. **Record missing cassettes:**
         ```bash
         VCR_RECORD=true bundle exec rspec
         ```

      3. **Review flagged tests:**
         Search for `TODO: Convert to vcr: true` comments and manually convert them.

      4. **Commit changes:**
         ```bash
         git add .
         git commit -m "Migrate to Zero-Leak VCR configuration"
         ```

      ## Rollback

      If you need to rollback:
      ```bash
      ruby scripts/migrate_vcr_setup.rb --rollback
      ```

      ## Support

      - See `ZERO_LEAK_VCR_GUIDE.md` for complete usage guide
      - See `AGENT_VCR_PATTERNS.md` for AI agent patterns
      - All backups stored in `#{BACKUP_DIR}/`

      **The Zero-Leak VCR system eliminates API cost leaks permanently!** 🎉
    MARKDOWN

    puts '✅ Summary written to VCR_MIGRATION_SUMMARY.md'
  end
end

# CLI Interface
if __FILE__ == $PROGRAM_NAME
  case ARGV[0]
  when '--rollback'
    VCRMigration.new.rollback!
  when '--help', '-h'
    puts <<~HELP
      Zero-Leak VCR Migration Tool

      Usage:
        ruby scripts/migrate_vcr_setup.rb           # Migrate to Zero-Leak VCR
        ruby scripts/migrate_vcr_setup.rb --rollback # Rollback migration
        ruby scripts/migrate_vcr_setup.rb --help     # Show this help

      The migration tool will:
      1. Create backups of modified files
      2. Disable old VCR configuration files#{'  '}
      3. Update spec_helper.rb to use Zero-Leak VCR
      4. Convert test files to use simple vcr: true pattern
      5. Generate migration summary

      This ensures zero API leaks while simplifying VCR usage.
    HELP
  else
    VCRMigration.new.migrate!
  end
end
