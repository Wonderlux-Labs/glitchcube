# frozen_string_literal: true

# Zero-Leak VCR Helpers
# Simple, agent-friendly VCR helpers that eliminate confusion
module ZeroLeakVCRHelpers
  # Generate automatic cassette name from test context
  def self.auto_cassette_name(example = nil)
    example ||= RSpec.current_example
    return 'default_cassette' unless example

    # Create clean, filesystem-safe name from test description
    description = example.full_description
                         .downcase
                         .gsub(/[^a-z0-9\s_-]/, '') # Remove special chars
                         .gsub(/\s+/, '_')            # Spaces to underscores
                         .squeeze('_')                # Remove duplicate underscores
                         .slice(0, 100)               # Limit length

    # Organize by spec file for easy navigation
    spec_file = example.file_path
                       .gsub(%r{^.*/spec/}, '')     # Remove spec/ prefix
                       .gsub(/_spec\.rb$/, '')      # Remove _spec.rb suffix
                       .gsub('/', '_')              # Slashes to underscores

    "#{spec_file}/#{description}"
  end

  # Main helper method - simple vcr: true usage
  def with_zero_leak_vcr(cassette_name = nil, options = {}, &)
    cassette_name ||= ZeroLeakVCRHelpers.auto_cassette_name

    # Smart defaults - agents don't need to think about these
    vcr_options = {
      match_requests_on: %i[method uri],
      allow_playback_repeats: true
    }.merge(options)

    VCR.use_cassette(cassette_name, vcr_options, &)
  end

  # Specific helpers for common API types (optional convenience)
  def with_openrouter_cassette(cassette_name = nil, &)
    cassette_name ||= "openrouter/#{ZeroLeakVCRHelpers.auto_cassette_name}"
    with_zero_leak_vcr(cassette_name, &)
  end

  def with_home_assistant_cassette(cassette_name = nil, &)
    cassette_name ||= "home_assistant/#{ZeroLeakVCRHelpers.auto_cassette_name}"
    with_zero_leak_vcr(cassette_name, &)
  end
end

# Configure RSpec to use Zero-Leak VCR automatically
RSpec.configure do |config|
  config.include ZeroLeakVCRHelpers

  # Automatic VCR for tests marked with vcr: true
  config.around(:each, :vcr) do |example|
    vcr_options = example.metadata[:vcr]

    if vcr_options == true
      # Simple case: vcr: true - use auto-generated cassette name
      with_zero_leak_vcr { example.run }
    elsif vcr_options.is_a?(Hash)
      # Complex case: vcr: { cassette_name: 'custom', other_options: value }
      cassette_name = vcr_options.delete(:cassette_name)
      options = vcr_options

      with_zero_leak_vcr(cassette_name, options) { example.run }
    else
      # Fallback: treat any truthy value as vcr: true
      with_zero_leak_vcr { example.run }
    end
  end

  # Automatic VCR for integration tests (optional)
  config.around(:each, type: :integration) do |example|
    # Only auto-apply if no explicit vcr metadata is set
    if example.metadata.key?(:vcr)
      example.run
    else
      with_zero_leak_vcr { example.run }
    end
  end
end
