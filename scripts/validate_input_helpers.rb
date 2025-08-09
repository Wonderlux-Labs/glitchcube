#!/usr/bin/env ruby
# frozen_string_literal: true

require 'yaml'
require 'pathname'

config_dir = Pathname.new('config/homeassistant/input_helpers')
errors = []
warnings = []

# Check each input helper type
%w[input_boolean input_button input_datetime input_number input_select input_text].each do |helper_type|
  type_dir = config_dir.join(helper_type)

  if type_dir.exist?
    puts "Checking #{helper_type}..."

    Dir.glob(type_dir.join('*.yaml')).each do |file|
      content = File.read(file)

      # Check for document separator
      warnings << "#{file}: Has document separator '---' which should be removed for !include_dir_merge_named" if content.start_with?('---')

      # Parse YAML
      yaml_content = YAML.safe_load(content)

      if yaml_content.nil? || yaml_content.empty?
        warnings << "#{file}: Empty file"
      else
        # Validate structure
        yaml_content.each do |key, value|
          unless value.is_a?(Hash)
            errors << "#{file}: Entity '#{key}' is not a hash"
            next
          end

          # Check required fields based on type
          case helper_type
          when 'input_text'
            warnings << "#{file}: Entity '#{key}' missing 'name' field" unless value.key?('name')
          when 'input_number'
            %w[min max].each do |required|
              errors << "#{file}: Entity '#{key}' missing required '#{required}' field" unless value.key?(required)
            end
          when 'input_select'
            errors << "#{file}: Entity '#{key}' missing required 'options' field" unless value.key?('options')
          when 'input_datetime'
            errors << "#{file}: Entity '#{key}' must have 'has_date' or 'has_time'" unless value.key?('has_date') || value.key?('has_time')
          end
        end
      end

      puts "  ✅ #{File.basename(file)}"
    rescue Psych::SyntaxError => e
      errors << "#{file}: YAML syntax error - #{e.message}"
    end
  else
    warnings << "Directory #{type_dir} does not exist"
  end
end

puts "\n#{'=' * 50}"
if errors.empty? && warnings.empty?
  puts '✅ All input helper files are valid!'
else
  if warnings.any?
    puts '⚠️  Warnings:'
    warnings.each { |w| puts "  - #{w}" }
  end

  if errors.any?
    puts '❌ Errors:'
    errors.each { |e| puts "  - #{e}" }
    exit 1
  end
end
