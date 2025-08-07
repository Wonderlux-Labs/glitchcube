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
# NOTE: Using real Home Assistant instance for tests - no mock needed

# Load environment variables - CI can override by setting before .env load
require 'dotenv'
Dotenv.load('.env.test', '.env')
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
  config.before do
    # Clean database between tests
    Memory.destroy_all if defined?(Memory)
    Message.destroy_all if defined?(Message)
    Conversation.destroy_all if defined?(Conversation)

    # Disable circuit breakers in tests via ENV variable (works in both local and CI)
    ENV['DISABLE_CIRCUIT_BREAKERS'] = 'true'

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

  config.filter_sensitive_data('<OPENROUTER_API_KEY>') { ENV.fetch('OPENROUTER_API_KEY', nil) }
  config.filter_sensitive_data('<HOME_ASSISTANT_TOKEN>') { ENV.fetch('HOME_ASSISTANT_TOKEN', nil) }

  # In CI, never allow new recordings - only use existing cassettes
  if ENV['CI'] == 'true'
    config.default_cassette_options = {
      record: :none,  # Fail if cassette doesn't exist
      match_requests_on: %i[method uri body]
    }
  else
    config.default_cassette_options = {
      record: :new_episodes,  # Allow recording locally
      match_requests_on: %i[method uri body]
    }
  end

  # Allow Home Assistant calls without cassettes during tests (local only)
  unless ENV['CI'] == 'true'
    config.ignore_request do |request|
      URI(request.uri).host&.match?(/\.local$/)
    end
  end

  # Add logging for VCR interactions (only in non-CI)
  unless ENV['CI'] == 'true'
    config.before_record do |interaction|
      puts "🎥 VCR Recording: #{interaction.request.method.upcase} #{interaction.request.uri}"
    end

    config.before_playback do |interaction|
      puts "▶️  VCR Playback: #{interaction.request.method.upcase} #{interaction.request.uri}"
    end
  end
end

# Disable all network connections in CI - only VCR cassettes allowed
if ENV['CI'] == 'true'
  WebMock.disable_net_connect!(allow_localhost: true)
  
  # In CI, fail immediately on any non-localhost request not handled by VCR
  WebMock.after_request do |request_signature, response|
    host = request_signature.uri.host
    unless host&.match?(/localhost|127\.0\.0\.1/)
      raise "❌ EXTERNAL NETWORK REQUEST IN CI: #{request_signature.method.upcase} #{request_signature.uri}\n" \
            "All external requests must use VCR cassettes in CI!"
    end
  end
else
  # Local development - allow .local domains for Home Assistant
  WebMock.disable_net_connect!(
    allow_localhost: true,
    allow: [/localhost/, /127\.0\.0\.1/, /\.local$/]
  )

  # Add callback to warn about any real HTTP requests that might slip through
  WebMock.after_request do |request_signature, response|
    host = request_signature.uri.host
    is_allowed_local = host&.match?(/localhost|127\.0\.0\.1|\.local$/)

    if response.status.first == 200 && !is_allowed_local
      puts "⚠️  LIVE HTTP REQUEST: #{request_signature.method.upcase} #{request_signature.uri}"
      puts '   This should be using a VCR cassette instead!'
    elsif is_allowed_local && host&.match?(/\.local$/)
      puts "📡 Home Assistant call: #{request_signature.method.upcase} #{request_signature.uri}"
      puts '   Consider recording this in a VCR cassette for consistent tests'
    end
  end
end
