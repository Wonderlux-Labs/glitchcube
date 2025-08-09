# frozen_string_literal: true

module VCRRequestTracker
  class << self
    attr_accessor :unhandled_requests

    def reset!
      @unhandled_requests = []
    end

    def track_request(request, example)
      return if example.nil? # Skip if we can't determine the test

      @unhandled_requests ||= []
      request_info = {
        example: example,
        request: request,
        location: example.location,
        description: example.full_description,
        file_path: example.file_path
      }
      @unhandled_requests << request_info

      # APPEND TO LOG IMMEDIATELY - don't wait for the end!
      log_file = File.join('logs', 'vcr_unhandled_requests.log')
      File.open(log_file, 'a') do |f|
        f.puts '❌ UNHANDLED REQUEST:'
        f.puts "   Test: #{request_info[:description]}"
        f.puts "   Location: #{request_info[:location]}"
        f.puts "   Request: #{request.method.upcase} #{request.uri}"
        f.puts "   Time: #{Time.now.iso8601}"
        f.puts "   Fix: VCR_OVERRIDE=true bundle exec rspec #{request_info[:location]}"
        f.puts '-' * 80
      end

      # Also tag the test so we can filter them
      return unless example.metadata

      example.metadata[:needs_vcr_cassette] = true
      example.metadata[:unhandled_requests] ||= []
      example.metadata[:unhandled_requests] << "#{request.method.upcase} #{request.uri}"
    end

    def generate_report
      return if @unhandled_requests.nil? || @unhandled_requests.empty?

      report = []
      report << "\n#{'=' * 80}"
      report << "🚨 VCR TRACKER SUMMARY: #{@unhandled_requests.size} test(s) made unhandled HTTP requests"
      report << ('=' * 80)

      # Group by file for easier batch fixing
      by_file = @unhandled_requests.group_by { |req| req[:file_path] }

      by_file.each do |file, requests|
        report << "\n📁 #{file}:"

        # Deduplicate by location to avoid showing the same test multiple times
        unique_requests = requests.uniq { |req| req[:location] }

        unique_requests.each do |req|
          report << "  ❌ #{req[:description]}"
          report << "     Location: #{req[:location]}"
          report << "     Request: #{req[:request].method.upcase} #{req[:request].uri}"
          report << ''
        end
      end

      # Generate RSpec commands for quick fixing
      report << "\n🔧 Quick Fix Commands:"
      report << "To record missing cassettes, run these commands:\n\n"

      unique_locations = @unhandled_requests.map { |req| req[:location] }.uniq
      unique_locations.each do |location|
        report << "  VCR_OVERRIDE=true bundle exec rspec #{location}"
      end

      report << "\n#{'=' * 80}"
      report << '💡 TIP: After recording, commit the new cassettes in spec/vcr_cassettes/'
      report << "#{'=' * 80}\n"

      # Write to file in logs directory
      log_file = File.join('logs', 'vcr_unhandled_requests.log')
      File.open(log_file, 'w') do |f|
        f.puts report.join("\n")
      end

      # Also output to console
      puts report.join("\n")
    end
  end
end

# Initialize tracker
VCRRequestTracker.reset!
