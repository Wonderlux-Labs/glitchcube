# frozen_string_literal: true

# Zero-Leak VCR Setup
# Complete bulletproof VCR configuration with WebMock integration

# Load required gems
require 'vcr'
require 'webmock/rspec'

# Load our Zero-Leak VCR configuration
require_relative 'vcr_config'
require_relative 'vcr_helpers_new'

# Initialize Zero-Leak VCR configuration
ZeroLeakVCR.configure!

# Configure WebMock for maximum security
WebMock.disable_net_connect!(
  # Only allow localhost connections for app testing
  allow_localhost: true,
  # Allow specific domains if needed for Selenium/browser testing
  allow: 'chromedriver.storage.googleapis.com'
)

# Secondary protection: Catch any external requests that bypass VCR
WebMock.after_request do |request_signature, _response|
  host = request_signature.uri.host

  # Skip if it's a legitimate localhost request
  next if host&.match?(/\A(localhost|127\.0\.0\.1|::1)\z/)

  # Skip if VCR is handling this request
  next if VCR.current_cassette

  # This should rarely trigger since VCR should catch it first
  # But provides a final safety net against API leaks
  error_msg = <<~ERROR
    🚨 EXTERNAL REQUEST BYPASSED VCR PROTECTION!

    Request: #{request_signature.method.upcase} #{request_signature.uri}
    Host: #{host}
    Test: #{RSpec.current_example&.location || 'Unknown test'}

    This is a critical security issue - the request somehow bypassed VCR's protection.

    Immediate action required:
    1. Use vcr: true in your test or wrap with VCR.use_cassette
    2. Record missing cassette: VCR_RECORD=true bundle exec rspec
    3. Check for any mocked HTTP libraries that might bypass VCR

    ALL external requests MUST go through VCR to prevent API cost leaks!
  ERROR

  # Log to file for tracking
  log_file = File.join('logs', 'vcr_bypass_errors.log')
  FileUtils.mkdir_p(File.dirname(log_file))
  File.open(log_file, 'a') do |f|
    f.puts "#{Time.now.iso8601}: #{error_msg}"
    f.puts '-' * 80
  end

  raise error_msg
end

# Additional RSpec configuration for Zero-Leak VCR
RSpec.configure do |config|
  # Ensure logs directory exists
  config.before(:suite) do
    FileUtils.mkdir_p('logs')

    # Display VCR mode message at start of test suite
    if ARGV.include?('--vcr-override')
      puts '🔄 VCR Override mode activated via command line'
    elsif ARGV.include?('--vcr-none')
      puts '🛡️ VCR None mode activated via command line (CI emulation)'
    end
  end

  # Tag tests that make external calls for easier identification
  config.before do |example|
    # Auto-tag integration tests
    example.metadata[:external_api] = true if example.file_path.include?('/integration/') && !example.metadata.key?(:vcr)

    # Auto-tag tests that use external API clients
    example.metadata[:external_api] = true if example.full_description.match?(/openrouter|home.assistant|github|api/i) && !example.metadata.key?(:vcr)
  end

  # Automatic VCR for tagged external API tests
  config.around(:each, :external_api) do |example|
    # Only auto-apply if no explicit vcr metadata
    example.metadata[:vcr] = true unless example.metadata.key?(:vcr)
    example.run
  end

  # Generate VCR report after test suite
  config.after(:suite) do
    generate_vcr_summary_report
  end
end

# Generate a summary report of VCR usage
def generate_vcr_summary_report
  report_file = File.join('logs', 'vcr_summary.log')

  File.open(report_file, 'w') do |f|
    f.puts "VCR SUMMARY REPORT - #{Time.now.iso8601}"
    f.puts '=' * 80
    f.puts

    # Count cassettes by type
    cassette_dir = File.join('spec', 'vcr_cassettes')
    if Dir.exist?(cassette_dir)
      cassettes = Dir.glob("#{cassette_dir}/**/*.yml")
      f.puts "📼 Total cassettes: #{cassettes.count}"

      # Group by directory
      by_directory = cassettes.group_by { |path| File.dirname(path).split('/')[-1] }
      by_directory.each do |dir, files|
        f.puts "   #{dir}: #{files.count} cassettes"
      end
    else
      f.puts '📼 No cassettes directory found'
    end

    f.puts
    f.puts '🔒 Zero-Leak VCR Status: ACTIVE'
    f.puts '   - External requests blocked without cassettes'
    f.puts '   - CI mode prevents recording'
    f.puts '   - Auto-generated cassette names'
    f.puts
    f.puts '💡 To record missing cassettes:'
    f.puts '   VCR_RECORD=true bundle exec rspec'
    f.puts
  end
end
