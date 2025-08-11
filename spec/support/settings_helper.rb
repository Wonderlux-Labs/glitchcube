# frozen_string_literal: true

module SettingsHelper
  # Preferred method: Use stub_const to mock ENV values safely
  def with_env_vars(vars)
    # Use stub_const instead of directly modifying ENV
    # This is safer and more predictable in tests
    # Handle nil values by removing them from the hash
    new_env = ENV.to_h.dup
    vars.each do |key, value|
      if value.nil?
        new_env.delete(key.to_s)
      else
        new_env[key.to_s] = value.to_s
      end
    end
    stub_const('ENV', new_env)
    yield
  end

  # Use Cube::Settings override mechanism instead of modifying ENV
  def with_settings_override(overrides)
    overrides.each do |key, value|
      Cube::Settings.override!(key, value)
    end

    yield
  ensure
    Cube::Settings.clear_overrides!
  end
end

RSpec.configure do |config|
  config.include SettingsHelper

  # Ensure overrides are cleared after each test
  config.after(:each) do
    Cube::Settings.clear_overrides!
  end
end
