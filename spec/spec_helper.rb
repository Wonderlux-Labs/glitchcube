# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  add_filter '/config/'
end

ENV['RACK_ENV'] = 'test'
# Note: Using real Home Assistant instance for tests - no mock needed

# Load environment variables - CI can override by setting before .env load
require 'dotenv'
Dotenv.load('.env.test', '.env')
# Fallback defaults if not set anywhere
ENV['OPENROUTER_API_KEY'] ||= 'test-api-key'
ENV['HOME_ASSISTANT_TOKEN'] ||= 'test-ha-token'

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
  end

  # Configure test environment settings
  config.before(:each) do
    # Disable circuit breakers in tests via ENV variable (works in both local and CI)
    ENV['DISABLE_CIRCUIT_BREAKERS'] = 'true'
    
    # Override GlitchCube config for tests
    if defined?(GlitchCube) && GlitchCube.respond_to?(:config)
      # Ensure AI config is available
      if GlitchCube.config.ai.nil?
        GlitchCube.config.ai = OpenStruct.new(
          default_model: 'google/gemini-2.5-flash',
          temperature: 0.8,
          max_tokens: 200
        )
      end
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

  config.default_cassette_options = {
    record: :new_episodes,
    match_requests_on: %i[method uri body]
  }

  # Allow Home Assistant calls without cassettes during tests
  config.ignore_request do |request|
    URI(request.uri).host&.match?(/\.local$/)
  end

  # Add logging for VCR interactions
  config.before_record do |interaction|
    puts "🎥 VCR Recording: #{interaction.request.method.upcase} #{interaction.request.uri}"
  end

  config.before_playback do |interaction|
    puts "▶️  VCR Playback: #{interaction.request.method.upcase} #{interaction.request.uri}"
  end
end

# Disable all network connections except to localhost and .local domains
# This prevents live API calls during tests - VCR cassettes should be used instead
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
    puts "   This should be using a VCR cassette instead!"
  elsif is_allowed_local && host&.match?(/\.local$/)
    puts "📡 Home Assistant call: #{request_signature.method.upcase} #{request_signature.uri}"
    puts "   Consider recording this in a VCR cassette for consistent tests"
  end
end
