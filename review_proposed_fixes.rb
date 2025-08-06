#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to review proposed fixes from the self-healing error handler
require 'json'
require 'colorize'
require 'optparse'

options = {
  format: 'terminal',
  status: 'pending',
  min_confidence: 0.0
}

OptionParser.new do |opts|
  opts.banner = 'Usage: review_proposed_fixes.rb [options]'

  opts.on('-f', '--format FORMAT', 'Output format (terminal, json, csv)') do |f|
    options[:format] = f
  end

  opts.on('-s', '--status STATUS', 'Filter by status (pending, approved, rejected, applied)') do |s|
    options[:status] = s
  end

  opts.on('-c', '--confidence MIN', Float, 'Minimum confidence threshold') do |c|
    options[:min_confidence] = c
  end

  opts.on('-d', '--days DAYS', Integer, 'Show fixes from last N days') do |d|
    options[:days] = d
  end
end.parse!

class ProposedFixReviewer
  def initialize(options)
    @options = options
    @log_dir = 'log/proposed_fixes'
  end

  def review
    fixes = load_fixes

    if fixes.empty?
      puts 'No proposed fixes found matching criteria'.yellow
      return
    end

    case @options[:format]
    when 'json'
      puts JSON.pretty_generate(fixes)
    when 'csv'
      output_csv(fixes)
    else
      output_terminal(fixes)
    end
  end

  private

  def load_fixes
    fixes = []

    Dir.glob("#{@log_dir}/*.jsonl").reverse.each do |file|
      # Check date filter
      if @options[:days]
        file_date = File.basename(file).match(/(\d{8})/)[1]
        file_time = Time.strptime(file_date, '%Y%m%d')
        next if file_time < Time.now - (@options[:days] * 86_400)
      end

      File.readlines(file).each do |line|
        fix = JSON.parse(line)

        # Apply filters
        next if fix['confidence'].to_f < @options[:min_confidence]

        fixes << fix
      end
    end

    fixes
  end

  def output_terminal(fixes)
    puts "\n📋 PROPOSED FIXES SUMMARY".bold
    puts '=' * 80

    # Group by confidence level
    high_confidence = fixes.select { |f| f['confidence'].to_f >= 0.85 }
    medium_confidence = fixes.select { |f| f['confidence'].to_f.between?(0.7, 0.85) }
    low_confidence = fixes.select { |f| f['confidence'].to_f < 0.7 }

    if high_confidence.any?
      puts "\n✅ HIGH CONFIDENCE (#{high_confidence.count} fixes)".green
      high_confidence.each { |fix| display_fix(fix) }
    end

    if medium_confidence.any?
      puts "\n⚠️  MEDIUM CONFIDENCE (#{medium_confidence.count} fixes)".yellow
      medium_confidence.each { |fix| display_fix(fix) }
    end

    if low_confidence.any?
      puts "\n❌ LOW CONFIDENCE (#{low_confidence.count} fixes)".red
      low_confidence.each { |fix| display_fix(fix) }
    end

    puts "\n#{'=' * 80}"
    puts 'STATISTICS:'.bold
    puts "  Total fixes proposed: #{fixes.count}"
    puts "  Critical issues: #{fixes.count { |f| f.dig('analysis', 'critical') }}"
    puts "  Average confidence: #{format('%.2f', fixes.map { |f| f['confidence'].to_f }.sum / fixes.count)}"

    # Show most common errors
    error_counts = fixes.group_by { |f| f.dig('error', 'class') }
      .transform_values(&:count)
      .sort_by { |_, v| -v }
      .first(5)

    return unless error_counts.any?

    puts "\n  Most common errors:"
    error_counts.each do |error_class, count|
      puts "    - #{error_class}: #{count} occurrences"
    end
  end

  def display_fix(fix)
    puts "\n  #{fix['timestamp'].split('T').first} - #{fix.dig('error', 'class')}".light_blue
    puts "    Error: #{fix.dig('error', 'message').truncate(80)}".white
    puts "    Service: #{fix.dig('context', 'service')} | Method: #{fix.dig('context', 'method')}".light_black
    puts "    Occurrences: #{fix.dig('error', 'occurrences')} | Confidence: #{'%.2f' % fix['confidence']}".light_black

    puts "    ⚠️  CRITICAL: #{fix.dig('analysis', 'reason')}".light_red if fix.dig('analysis', 'critical')

    puts "    Fix: #{fix.dig('proposed_fix', 'description')}".green if fix.dig('proposed_fix', 'description')

    return unless fix.dig('proposed_fix', 'files_modified')&.any?

    puts "    Files: #{fix.dig('proposed_fix', 'files_modified').join(', ')}".light_black
  end

  def output_csv(fixes)
    require 'csv'

    puts CSV.generate_line(['Timestamp', 'Error Class', 'Error Message', 'Service',
                            'Method', 'Occurrences', 'Confidence', 'Critical',
                            'Fix Description', 'Files'])

    fixes.each do |fix|
      puts CSV.generate_line([
                               fix['timestamp'],
                               fix.dig('error', 'class'),
                               fix.dig('error', 'message'),
                               fix.dig('context', 'service'),
                               fix.dig('context', 'method'),
                               fix.dig('error', 'occurrences'),
                               fix['confidence'],
                               fix.dig('analysis', 'critical'),
                               fix.dig('proposed_fix', 'description'),
                               fix.dig('proposed_fix', 'files_modified')&.join(';')
                             ])
    end
  end
end

# Add String#truncate if not available
unless String.method_defined?(:truncate)
  class String
    def truncate(max)
      length > max ? "#{self[0...max]}..." : self
    end
  end
end

# Run the reviewer
reviewer = ProposedFixReviewer.new(options)
reviewer.review
