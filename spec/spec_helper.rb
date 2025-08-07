# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  add_filter '/config/'

  # Continue generating coverage report even if tests fail
  at_exit do
    SimpleCov.result.format! if SimpleCov.running
  end
end

# Suppress SimpleCov error messages on test failures
SimpleCov.at_exit do
  SimpleCov.result.format!
end

ENV['RACK_ENV'] = 'test'

# Load environment variables - CI can override by setting before .env load
# Priority: .env > .env.test > .env.defaults (Dotenv.load uses first-wins)
require 'dotenv'
Dotenv.load('.env', '.env.test', '.env.defaults')
# Fallback defaults if not set anywhere
ENV['OPENROUTER_API_KEY'] ||= 'test-api-key'
ENV['HOME_ASSISTANT_TOKEN'] ||= 'test-ha-token'

# Configure database using centralized config
require_relative '../config/database_config'
configure_database!

# Disable AI Gateway in tests - use direct OpenRouter calls
ENV.delete('AI_GATEWAY_URL')
ENV.delete('HELICONE_API_KEY')

require File.expand_path('../app', __dir__)
require 'rspec'
require 'rack/test'
require 'vcr'
require 'webmock/rspec'

# Load support files
Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |f| require f }

RSpec.configure do |config|
  config.include Rack::Test::Methods

  def app
    GlitchCubeApp
  end

  # Global timeout for all examples - tests should be fast!
  config.around do |example|
    timeout_seconds = ENV['TEST_TIMEOUT']&.to_i || 10 # 10 second default

    begin
      Timeout.timeout(timeout_seconds) do
        example.run
      end
    rescue Timeout::Error
      raise "Test '#{example.full_description}' exceeded #{timeout_seconds} second timeout! Check for hanging network calls or infinite loops."
    end
  end

  # Disable background jobs during tests
  config.before(:suite) do
    require 'sidekiq/testing'
    Sidekiq::Testing.fake!

    # Ensure test database is properly migrated
    # ActiveRecord should already be connected via app.rb
    begin
      # Check if we can connect
      ActiveRecord::Base.connection
      # Run any pending migrations
      ActiveRecord::Migration.maintain_test_schema!
    rescue ActiveRecord::NoDatabaseError
      # Database doesn't exist, create it
      puts 'Creating test database...'
      system('RACK_ENV=test bundle exec rake db:create')
      system('RACK_ENV=test bundle exec rake db:migrate')
    end
  end

  # Configure test environment settings
  config.before do |_example|
    # No TTS mocking needed - HomeAssistantClient.speak() calls are recorded by VCR
    # All TTS now goes through Home Assistant service calls which VCR captures

    # No mocking of HomeAssistantClient - VCR handles all external calls

    # Clean Redis state between tests if available
    begin
      redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379')
      redis.flushdb
      redis.quit
    rescue StandardError
      # Redis might not be available for some tests, that's perfectly fine
      # Tests should be designed to work with or without Redis
    end

    # Clean database between tests
    Memory.destroy_all if defined?(Memory)
    Message.destroy_all if defined?(Message)
    Conversation.destroy_all if defined?(Conversation)

    # Reset circuit breakers if they exist (but don't disable them globally)
    Services::CircuitBreakerService.reset_all_breakers if defined?(Services::CircuitBreakerService) && Services::CircuitBreakerService.respond_to?(:reset_all_breakers)

    # Clear any Cube::Settings overrides
    Cube::Settings.clear_overrides! if defined?(Cube::Settings)

    # Override GlitchCube config for tests
    # Ensure AI config is available
    if defined?(GlitchCube) && GlitchCube.respond_to?(:config) && GlitchCube.config.ai.nil?
      GlitchCube.config.ai = OpenStruct.new(
        default_model: 'google/gemini-2.5-flash',
        temperature: 0.8,
        max_tokens: 200
      )
    end
  end

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = 'spec/examples.txt'
  config.disable_monkey_patching!
  config.warnings = true

  config.default_formatter = 'doc' if config.files_to_run.one?

  config.profile_examples = 10
  config.order = :random
  Kernel.srand config.seed

  # Clean up test files after each spec
  config.after do
    # Clean up any test context documents
    test_dirs = ['spec/fixtures/test_context_documents', 'spec/fixtures/test_memory_documents']
    test_dirs.each do |dir|
      FileUtils.rm_rf(dir)
    end
  end
end

VCR.configure do |config|
  config.cassette_library_dir = 'spec/vcr_cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Allow HTTP connections when recording new cassettes
  config.allow_http_connections_when_no_cassette = false # Still strict by default
  config.ignore_localhost = false # Record localhost calls too
  config.default_cassette_options = { record: :once } # Record ONCE by default

  # Automatic cassette naming from test description
  # NOTE: VCR doesn't have a naming_hook method - this was causing errors
  # config.naming_hook = lambda do |request|
  #   # Generate cassette name from current RSpec example if available
  #   if defined?(RSpec) && RSpec.respond_to?(:current_example) && RSpec.current_example
  #     example = RSpec.current_example
  #     name = example.full_description.downcase
  #                   .gsub(/[^a-z0-9\s_-]/, '')
  #                   .gsub(/\s+/, '_')
  #                   .squeeze('_')
  #                   .slice(0, 100)
  #
  #     spec_file = example.file_path.gsub(%r{^.*/spec/}, '')
  #                        .gsub(/_spec\.rb$/, '')
  #                        .gsub('/', '_')
  #
  #     "#{spec_file}/#{name}"
  #   else
  #     'default_cassette'
  #   end
  # end

  # Best practice: Use automatic cassette naming
  config.default_cassette_options = {
    # Smart recording: Record once if missing, otherwise replay
    record: ENV['VCR_RECORD'] == 'true' ? :new_episodes : :once,
    # Match on method, URI path, and body for deterministic matching
    match_requests_on: %i[method uri body],
    # Allow same request multiple times in a test
    allow_playback_repeats: true,
    # Serialize with UTF-8 encoding for consistency
    serialize_with: :yaml,
    preserve_exact_body_bytes: true,
    # Decode compressed responses for readability
    decode_compressed_response: true
  }

  # Filter sensitive data consistently
  config.filter_sensitive_data('<OPENROUTER_API_KEY>') { ENV.fetch('OPENROUTER_API_KEY', nil) }
  config.filter_sensitive_data('<HOME_ASSISTANT_TOKEN>') { ENV.fetch('HOME_ASSISTANT_TOKEN', nil) }
  config.filter_sensitive_data('<GITHUB_TOKEN>') { ENV.fetch('GITHUB_TOKEN', nil) }

  # Also filter in headers
  config.before_record do |interaction|
    # Handle both string and array Authorization headers
    auth_header = interaction.request.headers['Authorization']
    if auth_header.is_a?(Array)
      interaction.request.headers['Authorization'] = auth_header.map { |h| h.gsub(/Bearer .+/, 'Bearer <TOKEN>') }
    elsif auth_header.is_a?(String)
      interaction.request.headers['Authorization'] = auth_header.gsub(/Bearer .+/, 'Bearer <TOKEN>')
    end

    # Handle API key headers
    api_key = interaction.request.headers['X-Api-Key']
    if api_key.is_a?(Array)
      interaction.request.headers['X-Api-Key'] = api_key.map { |_k| '<API_KEY>' }
    elsif api_key.is_a?(String)
      interaction.request.headers['X-Api-Key'] = '<API_KEY>'
    end
  end

  # Fail fast on missing cassettes with helpful error
  config.before_http_request do |request|
    unless VCR.current_cassette
      raise VCR::Errors::UnhandledHTTPRequestError.new(request).tap do |_error|
        puts <<~ERROR
          ❌ NO VCR CASSETTE ACTIVE FOR REQUEST

          Request: #{request.method.upcase} #{request.uri}

          To fix:
          1. Wrap this test in VCR.use_cassette or use vcr: metadata
          2. Record locally: VCR_RECORD=true bundle exec rspec #{RSpec.current_example.location}
          3. Commit the cassette in spec/vcr_cassettes/
        ERROR
      end
    end
  end

  # Log VCR activity only when recording and not in CI
  if ENV['VCR_RECORD'] == 'true' && ENV['CI'] != 'true'
    # Track what we've already logged to avoid spam
    @vcr_logged_requests ||= Set.new

    config.before_record do |interaction|
      # interaction.request.uri might be a string or URI object
      uri = interaction.request.uri
      uri = URI.parse(uri) if uri.is_a?(String)
      request_key = "#{interaction.request.method.upcase} #{uri.host}#{uri.path}"
      unless @vcr_logged_requests.include?(request_key)
        puts "🎥 Recording: #{request_key}"
        @vcr_logged_requests.add(request_key)
      end
    end
  elsif ENV['CI'] != 'true' && ENV['VCR_DEBUG'] == 'true'
    # Only show playback in debug mode
    config.before_playback do |interaction|
      puts "▶️  Playing: #{interaction.request.method.upcase} #{interaction.request.uri}"
    end
  end
end

# STRICT: Block ALL external connections except localhost
# VCR will handle all external calls - no bypass allowed
WebMock.disable_net_connect!(
  allow_localhost: true,
  allow: 'chromedriver.storage.googleapis.com' # Only for Selenium if needed
)

# Fail immediately on any external request not handled by VCR
# But allow real requests when VCR is recording or playing back
WebMock.after_request do |request_signature, _response|
  host = request_signature.uri.host
  # Only allow true localhost requests
  unless host&.match?(/\A(localhost|127\.0\.0\.1|::1)\z/)
    # Skip this check if VCR is handling the request (recording or playing back)
    if VCR.current_cassette
      # VCR is handling this request, allow it
      next
    end

    error_msg = <<~ERROR
      ❌ EXTERNAL REQUEST ATTEMPTED WITHOUT VCR CASSETTE

      Request: #{request_signature.method.upcase} #{request_signature.uri}
      Host: #{host}
      Test: #{RSpec.current_example&.location}

      This request bypassed VCR! To fix:

      1. Use VCR.use_cassette in your test:
         VCR.use_cassette('cassette_name') do
           # your test code
         end

      2. Or use RSpec metadata:
         it 'does something', vcr: { cassette_name: 'my_cassette' } do
           # your test code
         end

      3. To record a new cassette:
         VCR_RECORD=true bundle exec rspec #{RSpec.current_example&.location}

      ALL external requests MUST go through VCR!
    ERROR

    raise error_msg
  end
end

# Additional safety check for CI
if ENV['CI'] == 'true'
  # In CI, we should NEVER record new cassettes
  VCR.configure do |config|
    config.before_record do |interaction|
      raise <<~ERROR
        ❌ VCR TRIED TO RECORD IN CI!

        Request: #{interaction.request.method.upcase} #{interaction.request.uri}

        This should never happen in CI. Cassettes must be recorded locally and committed.
        The test is missing a cassette or the cassette doesn't match the request.
      ERROR
    end
  end

  puts '✅ CI Mode: VCR will only replay existing cassettes'
elsif ENV['VCR_RECORD'] == 'true'
  puts '🎥 Recording Mode: VCR will record new episodes to cassettes'
  puts '   Remember to commit new/updated cassettes!'
else
  puts '▶️  Playback Mode: VCR will only replay existing cassettes'
  puts '   Use VCR_RECORD=true to record new cassettes'
end
