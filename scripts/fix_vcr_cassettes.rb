#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to systematically re-record VCR cassettes for failing tests
# This script identifies failing tests from logs and re-records their cassettes

require 'fileutils'

class VCRCassetteFixer
  def initialize
    @base_dir = Dir.pwd
    @cassette_dir = File.join(@base_dir, 'spec', 'vcr_cassettes')
    @logs_dir = File.join(@base_dir, 'logs')
  end

  def run
    puts '🎬 VCR Cassette Fixer Starting...'
    puts "   Base Directory: #{@base_dir}"
    puts "   Cassette Directory: #{@cassette_dir}"
    puts ''

    # Read failing tests from logs
    failing_tests = extract_failing_tests_from_logs

    if failing_tests.empty?
      puts '✅ No failing tests found in logs'
      return
    end

    puts "📋 Found #{failing_tests.size} failing tests:"
    failing_tests.each { |test| puts "   - #{test}" }
    puts ''

    # Re-record cassettes for each failing test
    failing_tests.each do |test_location|
      re_record_cassette(test_location)
    end

    puts '🎉 VCR Cassette recording completed!'
    puts ''
    puts 'Next Steps:'
    puts '1. Run: git add spec/vcr_cassettes/'
    puts "2. Run: git commit -m 'Re-record VCR cassettes for failing tests'"
    puts '3. Run: bundle exec rspec [failing_test_files] to verify fixes'
  end

  private

  def extract_failing_tests_from_logs
    failing_tests = []

    # Extract from VCR missing cassettes log
    missing_cassettes_log = File.join(@logs_dir, 'vcr_missing_cassettes.log')
    if File.exist?(missing_cassettes_log)
      File.readlines(missing_cassettes_log).each do |line|
        if line.include?('Test: ./') && !line.include?('unknown test')
          test_location = line.strip.gsub(/.*Test: /, '').gsub(/Fix:.*/, '').strip
          failing_tests << test_location unless test_location.empty?
        end
      end
    end

    # Extract from unhandled requests log
    unhandled_log = File.join(@logs_dir, 'vcr_unhandled_requests.log')
    if File.exist?(unhandled_log)
      File.read(unhandled_log).scan(%r{Location: (\./spec/.*:\d+)}).each do |match|
        failing_tests << match[0]
      end
    end

    failing_tests.uniq.sort
  end

  def re_record_cassette(test_location)
    puts "🎥 Recording cassette for: #{test_location}"

    command = "VCR_OVERRIDE=true bundle exec rspec #{test_location} --format progress"

    puts "   Command: #{command}"

    # Run with timeout to avoid hanging tests
    result = system("timeout 120 #{command}")

    if result
      puts '   ✅ Successfully recorded cassette'
    else
      puts '   ❌ Failed to record cassette (timeout or error)'
      puts "   💡 Try recording manually: #{command}"
    end

    puts ''
  end
end

# Run the fixer
VCRCassetteFixer.new.run
