# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  add_filter '/spec/'
  add_filter '/config/'
end

ENV['RACK_ENV'] = 'test'
# Note: Using real Home Assistant instance for tests - no mock needed

# Set test API keys - load from .env if available, otherwise use test defaults
require 'dotenv'
Dotenv.load('.env')
ENV['OPENROUTER_API_KEY'] ||= 'test-api-key'
ENV['HOME_ASSISTANT_TOKEN'] ||= 'test-ha-token'

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
end

# Disable all network connections except to localhost
WebMock.disable_net_connect!(allow_localhost: true)
