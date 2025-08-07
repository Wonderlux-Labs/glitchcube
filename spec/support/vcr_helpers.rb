# frozen_string_literal: true

# VCR Helper Methods for Consistent Cassette Usage
module VCRHelpers
  # Generate deterministic cassette name from example metadata
  def self.cassette_name_for(example)
    # Use example's full description, sanitized for filesystem
    name = example.full_description.downcase
                  .gsub(/[^a-z0-9\s_-]/, '') # Remove special chars
                  .gsub(/\s+/, '_')           # Replace spaces with underscores
                  .squeeze('_')               # Remove duplicate underscores
                  .slice(0, 100)              # Limit length for filesystem
    
    # Group by spec file for organization
    spec_file = example.file_path.gsub(%r{^.*/spec/}, '')
                       .gsub(/_spec\.rb$/, '')
                       .gsub('/', '_')
    
    "#{spec_file}/#{name}"
  end

  # Configure VCR for a specific test with best practices
  def with_vcr_cassette(name = nil, &block)
    cassette_name = name || VCRHelpers.cassette_name_for(RSpec.current_example)
    
    options = {
      record: ENV['VCR_RECORD'] == 'true' ? :new_episodes : :none,
      match_requests_on: %i[method uri body],
      allow_playback_repeats: true
    }
    
    VCR.use_cassette(cassette_name, options, &block)
  end

  # Helper for tests that need OpenRouter API calls
  def with_openrouter_cassette(name = nil, &block)
    cassette_name = name || "openrouter/#{VCRHelpers.cassette_name_for(RSpec.current_example)}"
    with_vcr_cassette(cassette_name, &block)
  end

  # Helper for tests that need Home Assistant API calls
  def with_home_assistant_cassette(name = nil, &block)
    cassette_name = name || "home_assistant/#{VCRHelpers.cassette_name_for(RSpec.current_example)}"
    with_vcr_cassette(cassette_name, &block)
  end
end

# Include helpers in RSpec
RSpec.configure do |config|
  config.include VCRHelpers

  # VCR metadata is handled by VCR's configure_rspec_metadata! in spec_helper
  # Don't handle it here to avoid conflicts

  # Disabled automatic VCR for integration specs to avoid conflicts
  # Integration specs should use explicit vcr: metadata

  # Auto-use VCR for any spec that makes external calls
  config.around(:each, :external_api) do |example|
    with_vcr_cassette { example.run }
  end
end