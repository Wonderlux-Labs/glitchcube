#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to automatically fix TODO comments from VCR migration

require 'fileutils'

class VCRTodoFixer
  def initialize(root_path = '.')
    @root_path = root_path
    @fixed_count = 0
    @files_modified = []
  end

  def fix_all!
    puts '🔧 Fixing VCR TODO comments...'
    puts '=' * 50

    # Find all spec files with TODOs
    spec_files = Dir.glob("#{@root_path}/spec/**/*_spec.rb")

    spec_files.each do |file|
      content = File.read(file)
      next unless content.include?('TODO: Convert to vcr: true')

      original_content = content.dup

      # Fix pattern: # TODO: Convert to vcr: true - VCR.use_cassette('name') do ... end
      # This was compressed to one line by the migration script
      content = content.gsub(/# TODO: Convert to vcr: true - (.*?)end/) do |match|
        full_line = ::Regexp.last_match(1)

        # Extract the cassette content between 'do' and the compressed 'end'
        if full_line =~ /VCR\.use_cassette\([^)]+\)\s+do\s+(.*)/
          cassette_content = ::Regexp.last_match(1).strip

          # Restore the original formatting
          # Remove multiple spaces that were added during compression
          cassette_content = cassette_content.gsub(/\s{2,}/, "\n          ")

          # The content was the body of the VCR.use_cassette block
          # Just return it without the VCR wrapper
          "#{cassette_content}\n        end"
        else
          # Couldn't parse, leave as is
          match
        end
      end

      # If content changed, write it back
      next unless content != original_content

      File.write(file, content)
      @fixed_count += 1
      @files_modified << File.basename(file)
      puts "  Fixed: #{File.basename(file)}"
    end

    puts "\n✅ Fixed #{@fixed_count} files"
    puts "Modified files: #{@files_modified.join(', ')}" if @files_modified.any?

    # Now ensure all tests have vcr: true where needed
    add_vcr_metadata!
  end

  def add_vcr_metadata!
    puts "\n🔧 Adding vcr: true metadata to tests that need it..."

    spec_files = Dir.glob("#{@root_path}/spec/**/*_spec.rb")
    metadata_added = 0

    spec_files.each do |file|
      content = File.read(file)
      original_content = content.dup

      # Look for tests that still have VCR.use_cassette patterns in comments
      # or tests that look like they make external calls
      if content.include?('VCR.use_cassette') ||
         content.match?(/openrouter|home.assistant|api|http|client\.speak|client\.call/)

        # Add vcr: true to tests that don't have it already
        content = content.gsub(/(\s+it\s+['"][^'"]+['"])(\s+do)/) do |match|
          test_declaration = ::Regexp.last_match(1)
          do_keyword = ::Regexp.last_match(2)

          # Check if this test already has vcr metadata
          if match.include?('vcr:')
            match
          else
            # Add vcr: true
            "#{test_declaration}, vcr: true#{do_keyword}"
          end
        end
      end

      next unless content != original_content

      File.write(file, content)
      metadata_added += 1
      puts "  Added vcr: true to tests in: #{File.basename(file)}"
    end

    puts "✅ Added vcr: true metadata to #{metadata_added} files"
  end
end

# Run the fixer
if __FILE__ == $PROGRAM_NAME
  fixer = VCRTodoFixer.new
  fixer.fix_all!

  puts "\n📋 Next steps:"
  puts '1. Review the changes: git diff'
  puts '2. Run tests to verify: bundle exec rspec'
  puts '3. Record missing cassettes: bundle exec rspec (auto-records in dev mode)'
  puts '4. Commit the changes'
end
