#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to identify and clean up orphaned entities, automations, and scripts in Home Assistant config

require 'yaml'
require 'fileutils'

class HAConfigCleaner
  def initialize(config_path = 'config/homeassistant')
    @config_path = config_path
    @packages_path = File.join(@config_path, 'packages')
    @entities_referenced = Set.new
    @entities_defined = Set.new
    @automations = []
    @scripts = []
    @issues = []
  end

  def analyze
    puts '🔍 Analyzing Home Assistant configuration...'

    # Scan all package files
    Dir.glob(File.join(@packages_path, '*.yaml')).each do |file|
      analyze_file(file)
    end

    report_findings
  end

  private

  def analyze_file(file)
    puts "  Checking #{File.basename(file)}..."

    begin
      content = YAML.load_file(file)

      # Check for input helpers
      %w[input_boolean input_number input_text input_select input_datetime counter timer].each do |domain|
        next unless content[domain]

        content[domain].each_key do |entity|
          @entities_defined.add("#{domain}.#{entity}")
        end
      end

      # Check for template sensors
      content['template']&.each do |template_type|
        next unless template_type.is_a?(Hash)

        template_type.each do |type, entities|
          next unless entities.is_a?(Array)

          entities.each do |entity|
            if entity['unique_id']
              # Template sensors use unique_id
              @entities_defined.add("#{type.gsub('_', '.')}.#{entity['unique_id']}")
            end
          end
        end
      end

      # Check for automations
      content['automation']&.each do |automation|
        @automations << {
          file: File.basename(file),
          id: automation['id'],
          alias: automation['alias'],
          triggers: extract_entities_from_config(automation['trigger']),
          conditions: extract_entities_from_config(automation['condition']),
          actions: extract_entities_from_config(automation['action'])
        }
      end

      # Check for scripts
      content['script']&.each do |script_name, script_config|
        @scripts << {
          file: File.basename(file),
          name: script_name,
          alias: script_config['alias'],
          entities: extract_entities_from_config(script_config['sequence'])
        }
      end

      # Extract all entity references from the file
      extract_entity_references(content)
    rescue StandardError => e
      @issues << "Error parsing #{File.basename(file)}: #{e.message}"
    end
  end

  def extract_entities_from_config(config)
    entities = Set.new
    return entities unless config

    # Recursively search for entity_id references
    case config
    when Hash
      config.each do |key, value|
        if key == 'entity_id'
          case value
          when String
            entities.add(value)
          when Array
            value.each { |e| entities.add(e) if e.is_a?(String) }
          end
        else
          entities.merge(extract_entities_from_config(value))
        end
      end
    when Array
      config.each { |item| entities.merge(extract_entities_from_config(item)) }
    when String
      # Check for template references
      config.scan(/states\(['"]([^'"]+)['"]\)/).each { |match| entities.add(match[0]) }
      config.scan(/is_state\(['"]([^'"]+)['"]/).each { |match| entities.add(match[0]) }
      config.scan(/state_attr\(['"]([^'"]+)['"]/).each { |match| entities.add(match[0]) }
    end

    entities
  end

  def extract_entity_references(config, depth = 0)
    return if depth > 10 # Prevent infinite recursion

    case config
    when Hash
      config.each_value { |v| extract_entity_references(v, depth + 1) }
    when Array
      config.each { |item| extract_entity_references(item, depth + 1) }
    when String
      # Extract entity references from templates
      config.scan(/states\(['"]([^'"]+)['"]\)/).each { |match| @entities_referenced.add(match[0]) }
      config.scan(/is_state\(['"]([^'"]+)['"]/).each { |match| @entities_referenced.add(match[0]) }
      config.scan(/state_attr\(['"]([^'"]+)['"]/).each { |match| @entities_referenced.add(match[0]) }

      # Extract direct entity_id references
      if config.match?(/^(sensor|binary_sensor|input_boolean|input_text|input_number|switch|light|climate|device_tracker|counter|timer)\.\w+$/)
        @entities_referenced.add(config)
      end
    end
  end

  def report_findings
    puts "\n📊 ANALYSIS RESULTS"
    puts '=' * 60

    # Report undefined entities
    undefined = @entities_referenced - @entities_defined
    undefined.reject! { |e| e.include?('.') && !e.start_with?('input_', 'counter.', 'timer.') }

    if undefined.any?
      puts "\n⚠️  UNDEFINED ENTITIES REFERENCED:"
      undefined.sort.each do |entity|
        puts "  - #{entity}"

        # Find which automations/scripts reference this entity
        @automations.each do |auto|
          all_entities = auto[:triggers] + auto[:conditions] + auto[:actions]
          if all_entities.include?(entity)
            puts "    └─ Used in automation: #{auto[:alias]} (#{auto[:file]})"
          end
        end

        @scripts.each do |script|
          if script[:entities].include?(entity)
            puts "    └─ Used in script: #{script[:alias]} (#{script[:file]})"
          end
        end
      end
    end

    # Report duplicate automation IDs
    automation_ids = @automations.map { |a| a[:id] }
    duplicates = automation_ids.select { |id| automation_ids.count(id) > 1 }.uniq

    if duplicates.any?
      puts "\n⚠️  DUPLICATE AUTOMATION IDS:"
      duplicates.each do |id|
        puts "  - #{id}:"
        @automations.select { |a| a[:id] == id }.each do |auto|
          puts "    └─ #{auto[:alias]} in #{auto[:file]}"
        end
      end
    end

    # Report issues
    if @issues.any?
      puts "\n❌ PARSING ISSUES:"
      @issues.each { |issue| puts "  - #{issue}" }
    end

    # Summary
    puts "\n📈 SUMMARY:"
    puts "  - Total automations: #{@automations.size}"
    puts "  - Total scripts: #{@scripts.size}"
    puts "  - Entities defined: #{@entities_defined.size}"
    puts "  - Entities referenced: #{@entities_referenced.size}"
    puts "  - Undefined entities: #{undefined.size}"
    puts "  - Duplicate automation IDs: #{duplicates.size}"

    # Generate fix suggestions
    return unless undefined.any?

    puts "\n💡 SUGGESTED FIXES:"
    puts '  Add these to a package file to define missing entities:'
    puts "\n# Missing input booleans"
    puts 'input_boolean:'
    undefined.select { |e| e.start_with?('input_boolean.') }.each do |entity|
      name = entity.split('.').last
      puts "  #{name}:"
      puts "    name: #{name.gsub('_', ' ').capitalize}"
      puts '    initial: false'
    end

    puts "\n# Missing input texts"
    puts 'input_text:'
    undefined.select { |e| e.start_with?('input_text.') }.each do |entity|
      name = entity.split('.').last
      puts "  #{name}:"
      puts "    name: #{name.gsub('_', ' ').capitalize}"
      puts "    initial: ''"
    end

    puts "\n# Missing counters"
    puts 'counter:'
    undefined.select { |e| e.start_with?('counter.') }.each do |entity|
      name = entity.split('.').last
      puts "  #{name}:"
      puts "    name: #{name.gsub('_', ' ').capitalize}"
      puts '    initial: 0'
    end
  end
end

# Run the analyzer
if __FILE__ == $0
  cleaner = HAConfigCleaner.new
  cleaner.analyze
end
