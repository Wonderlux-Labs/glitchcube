# frozen_string_literal: true

# VCR Cassette Management Helpers
# Tools for managing, validating, and maintaining VCR cassettes
module VCRManagement
  class << self
    # Validate all cassettes for security issues
    def validate_cassette_security(cassette_dir = 'spec/vcr_cassettes') # rubocop:disable Naming/PredicateMethod
      puts '🔍 Scanning VCR cassettes for security issues...'

      issues = []
      cassette_files = Dir.glob("#{cassette_dir}/**/*.yml")

      cassette_files.each do |file|
        file_issues = validate_single_cassette(file)
        issues.concat(file_issues) if file_issues.any?
      end

      if issues.any?
        puts "\n❌ Found #{issues.count} security issues:"
        issues.each { |issue| puts "   #{issue}" }

        # Write detailed report
        write_security_report(issues)
        false
      else
        puts '✅ All cassettes appear secure'
        true
      end
    end

    # Generate a report of cassette ages and suggest updates
    def cassette_age_report(cassette_dir = 'spec/vcr_cassettes', days_old: 30)
      puts '📊 Generating cassette age report...'

      cassette_files = Dir.glob("#{cassette_dir}/**/*.yml")
      old_cassettes = []

      cassette_files.each do |file|
        file_age = (Time.now - File.mtime(file)) / (24 * 60 * 60) # days

        next unless file_age > days_old

        old_cassettes << {
          file: file.gsub("#{cassette_dir}/", ''),
          age_days: file_age.round(1),
          last_modified: File.mtime(file).strftime('%Y-%m-%d')
        }
      end

      if old_cassettes.any?
        puts "\n📅 Found #{old_cassettes.count} cassettes older than #{days_old} days:"
        old_cassettes.sort_by { |c| c[:age_days] }.reverse.each do |cassette|
          puts "   #{cassette[:file]} (#{cassette[:age_days]} days old, #{cassette[:last_modified]})"
        end

        puts "\n💡 Consider refreshing old cassettes with:"
        puts '   VCR_RECORD=true bundle exec rspec'

        old_cassettes
      else
        puts "✅ All cassettes are fresh (less than #{days_old} days old)"
        []
      end
    end

    # Create smart cassette matchers for Home Assistant requests
    def create_smart_ha_matcher
      VCR.configure do |config|
        # Custom matcher that ignores changing entity IDs but matches the service call pattern
        config.register_request_matcher :ha_service_call do |r1, r2|
          # Match method and basic URI structure
          return false unless r1.method == r2.method

          uri1 = URI.parse(r1.uri)
          uri2 = URI.parse(r2.uri)

          # Match host and base path
          return false unless uri1.host == uri2.host && uri1.port == uri2.port

          # For HA API calls, match the service pattern
          if r1.uri.include?('/api/services/')
            # Extract domain/service from path
            path1_parts = uri1.path.split('/')
            path2_parts = uri2.path.split('/')

            # Match if same service endpoint structure
            return path1_parts[0..3] == path2_parts[0..3] # /api/services/domain/service
          end

          # For other calls, use standard URI matching
          uri1.path == uri2.path
        end

        # Custom matcher for entity state queries that ignores specific entity IDs
        config.register_request_matcher :ha_entity_state do |r1, r2|
          return false unless r1.method == r2.method

          uri1 = URI.parse(r1.uri)
          uri2 = URI.parse(r2.uri)

          # Match host and port
          return false unless uri1.host == uri2.host && uri1.port == uri2.port

          # For entity state queries, match the pattern but not specific entity ID
          if r1.uri.include?('/api/states/')
            # Extract domain from entity_id
            entity1 = uri1.path.split('/').last
            entity2 = uri2.path.split('/').last

            domain1 = entity1.split('.').first
            domain2 = entity2.split('.').first

            # Match if same domain (light.*, sensor.*, etc.)
            return domain1 == domain2
          end

          # For other calls, use exact path matching
          uri1.path == uri2.path
        end
      end
    end

    # Refresh Home Assistant cassettes that depend on entity changes
    def refresh_ha_cassettes(pattern: '**/home_assistant/**/*.yml')
      puts '🔄 Refreshing Home Assistant cassettes...'

      ha_cassettes = Dir.glob("spec/vcr_cassettes/#{pattern}")

      if ha_cassettes.empty?
        puts 'No Home Assistant cassettes found to refresh'
        return
      end

      puts "Found #{ha_cassettes.count} HA cassettes to refresh:"
      ha_cassettes.each { |file| puts "   #{file}" }

      # Backup existing cassettes
      backup_dir = "spec/vcr_cassettes_backup_#{Time.now.strftime('%Y%m%d_%H%M%S')}"
      FileUtils.mkdir_p(backup_dir)

      ha_cassettes.each do |cassette|
        backup_path = cassette.gsub('spec/vcr_cassettes', backup_dir)
        FileUtils.mkdir_p(File.dirname(backup_path))
        FileUtils.cp(cassette, backup_path)
      end

      puts "✅ Backed up cassettes to #{backup_dir}"

      # Remove old cassettes to force re-recording
      ha_cassettes.each { |file| File.delete(file) }

      puts '🎬 Cassettes removed. Run tests with VCR_RECORD=true to regenerate.'
      puts '   Example: VCR_RECORD=true bundle exec rspec spec/integration/'
    end

    # Clean up test artifacts and temporary files
    def cleanup_test_artifacts
      puts '🧹 Cleaning up test artifacts...'

      # Remove temporary VCR files
      temp_files = Dir.glob('spec/vcr_cassettes/**/*.tmp')
      temp_files.each { |file| File.delete(file) }

      # Remove empty directories
      Dir.glob('spec/vcr_cassettes/**/').reverse_each do |dir|
        Dir.rmdir(dir) if Dir.empty?(dir)
      rescue SystemCallError
        # Directory not empty, that's fine
      end

      # Clean up old backup directories (older than 7 days)
      old_backups = Dir.glob('spec/vcr_cassettes_backup_*').select do |dir|
        timestamp = dir.match(/\d{8}_\d{6}$/)&.to_s
        if timestamp
          backup_time = Time.strptime(timestamp, '%Y%m%d_%H%M%S')
          (Time.now - backup_time) > (7 * 24 * 60 * 60) # 7 days
        end
      end

      old_backups.each { |dir| FileUtils.rm_rf(dir) }

      puts "✅ Cleaned up #{temp_files.count} temp files and #{old_backups.count} old backups"
    end

    private

    def validate_single_cassette(file_path)
      issues = []

      begin
        content = File.read(file_path)

        # Check for common security issues
        if content.include?('Bearer sk-') || content.include?('Bearer eyJ')
          issues << "#{file_path}: Contains bearer token"
        end

        if content.match?(/[a-f0-9]{64}/) && !content.include?('<TOKEN>')
          issues << "#{file_path}: Contains potential hex token"
        end

        if content.include?('glitch.local') && !content.include?('<HA_HOST>')
          issues << "#{file_path}: Contains unfiltered hostname"
        end

        if content.match?(/\d+\.\d+\.\d+\.\d+/) && !content.include?('<HA_IP>')
          issues << "#{file_path}: Contains unfiltered IP address"
        end

        # Check for GPS coordinates
        if content.match?(/"latitude":\s*-?\d+\.\d+/) && !content.include?('<LATITUDE>')
          issues << "#{file_path}: Contains unfiltered GPS coordinates"
        end

        if content.match?(/"longitude":\s*-?\d+\.\d+/) && !content.include?('<LONGITUDE>')
          issues << "#{file_path}: Contains unfiltered GPS coordinates"
        end
      rescue StandardError => e
        issues << "#{file_path}: Error reading file - #{e.message}"
      end

      issues
    end

    def write_security_report(issues)
      report_file = File.join('logs', 'vcr_security_report.log')
      FileUtils.mkdir_p(File.dirname(report_file))

      File.open(report_file, 'w') do |f|
        f.puts "VCR SECURITY REPORT - #{Time.now.iso8601}"
        f.puts '=' * 80
        f.puts
        f.puts "Found #{issues.count} security issues in VCR cassettes:"
        f.puts

        issues.each do |issue|
          f.puts "❌ #{issue}"
        end

        f.puts
        f.puts 'RECOMMENDATIONS:'
        f.puts '1. Review the flagged cassettes manually'
        f.puts '2. Delete cassettes with sensitive data'
        f.puts '3. Re-record with improved filtering'
        f.puts '4. Update VCR configuration if needed'
        f.puts
        f.puts 'To re-record:'
        f.puts 'VCR_RECORD=true bundle exec rspec path/to/spec.rb'
      end

      puts "📄 Detailed report written to #{report_file}"
    end
  end
end

# Add Rake tasks for cassette management
if defined?(Rake)
  namespace :vcr do
    desc 'Validate all VCR cassettes for security issues'
    task :validate do
      VCRManagement.validate_cassette_security
    end

    desc 'Generate report of old cassettes that may need refreshing'
    task :age_report, [:days] do |_t, args|
      days = args[:days]&.to_i || 30
      VCRManagement.cassette_age_report(days_old: days)
    end

    desc 'Refresh Home Assistant cassettes'
    task :refresh_ha do
      VCRManagement.refresh_ha_cassettes
    end

    desc 'Clean up test artifacts and old backups'
    task :cleanup do
      VCRManagement.cleanup_test_artifacts
    end

    desc 'Full maintenance: validate, report, and cleanup'
    task :maintain do
      Rake::Task['vcr:validate'].invoke
      Rake::Task['vcr:age_report'].invoke
      Rake::Task['vcr:cleanup'].invoke
    end
  end
end
