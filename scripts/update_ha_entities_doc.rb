#!/usr/bin/env ruby
# frozen_string_literal: true

# Script to update Home Assistant entities documentation
require 'bundler/setup'
require_relative '../app'
require 'json'
require 'time'

class HAEntitiesDocUpdater
  def initialize
    @ha_client = HomeAssistantClient.new
    @doc_path = File.join(File.dirname(__FILE__), '..', 'docs', 'home_assistant_entities.md')
  end

  def update_documentation
    puts "📊 Fetching Home Assistant entities..."
    
    begin
      states = @ha_client.states
      
      if states.nil? || states.empty?
        puts "❌ No entities found or Home Assistant is not accessible"
        return false
      end
      
      puts "✅ Found #{states.count} entities"
      
      # Organize entities by domain
      entities_by_domain = organize_by_domain(states)
      
      # Check which entities are used in code
      used_entities = check_used_entities(states)
      
      # Generate the documentation
      doc_content = generate_documentation(entities_by_domain, states, used_entities)
      
      # Write to file
      File.write(@doc_path, doc_content)
      puts "✅ Documentation updated at: #{@doc_path}"
      
      # Print summary
      print_summary(entities_by_domain)
      
      true
    rescue StandardError => e
      puts "❌ Error updating documentation: #{e.message}"
      puts e.backtrace.first(5)
      false
    end
  end

  private

  def organize_by_domain(states)
    entities_by_domain = {}
    
    states.each do |state|
      entity_id = state['entity_id']
      domain = entity_id.split('.').first
      
      entities_by_domain[domain] ||= []
      entities_by_domain[domain] << state
    end
    
    # Sort domains and entities within each domain
    entities_by_domain.sort.to_h.transform_values { |entities| entities.sort_by { |e| e['entity_id'] } }
  end

  def check_used_entities(states)
    # List of entities referenced in the codebase
    used_entity_ids = [
      'input_text.current_weather',
      'input_text.current_persona',
      'input_text.current_environment',
      'input_text.camera_vision_analysis',
      'sensor.battery_level',
      'sensor.temperature',
      'sensor.outdoor_temperature',
      'sensor.outdoor_humidity',
      'sensor.playa_weather_api',
      'binary_sensor.motion',
      'binary_sensor.camera_motion',
      'camera.glitch_cube',
      'camera.camera',
      'camera.tablet',
      'media_player.glitch_cube_speaker',
      'device_tracker.glitch_cube',
      'input_number.glitch_cube_lat',
      'input_number.glitch_cube_lng',
      'input_number.glitch_cube_prev_lat',
      'input_number.glitch_cube_prev_lng',
      'sensor.camera_vision_status',
      'sensor.camera_people_count',
      'weather.openweathermap'
    ]
    
    # Check which ones exist
    existing_entity_ids = states.map { |s| s['entity_id'] }
    
    used_entities = {}
    used_entity_ids.each do |entity_id|
      if existing_entity_ids.include?(entity_id)
        state = states.find { |s| s['entity_id'] == entity_id }
        used_entities[entity_id] = {
          exists: true,
          state: state['state'],
          friendly_name: state.dig('attributes', 'friendly_name') || entity_id
        }
      else
        used_entities[entity_id] = {
          exists: false
        }
      end
    end
    
    used_entities
  end

  def generate_documentation(entities_by_domain, states, used_entities)
    timestamp = Time.now.strftime('%Y-%m-%d %H:%M:%S')
    total_entities = states.count
    
    doc = []
    doc << "# Home Assistant Entities"
    doc << ""
    doc << "✅ **Status**: Connected to Home Assistant at #{GlitchCube.config.home_assistant.url}"
    doc << "Generated on: #{timestamp}"
    doc << "Total entities: #{total_entities}"
    doc << ""
    doc << "## Entity Summary by Domain"
    doc << ""
    
    # Summary list
    entities_by_domain.each do |domain, entities|
      doc << "- **#{domain}**: #{entities.count} entities"
    end
    
    doc << ""
    doc << "## Glitch Cube Integration Status"
    doc << ""
    doc << "### Entities Used in Code:"
    
    # Show used entities
    used_entities.each do |entity_id, info|
      if info[:exists]
        doc << "- ✅ **#{entity_id}** - #{info[:friendly_name]} (State: #{info[:state]})"
      else
        doc << "- ❌ **#{entity_id}** - (Missing - needs configuration)"
      end
    end
    
    doc << ""
    doc << "### Key Available Entities:"
    
    # Highlight important available entities
    weather_entities = entities_by_domain['weather'] || []
    camera_entities = entities_by_domain['camera'] || []
    media_entities = entities_by_domain['media_player'] || []
    sensor_entities = entities_by_domain['sensor'] || []
    
    doc << "- **Weather entities**: #{weather_entities.count} #{weather_entities.map { |e| e['entity_id'] }.join(', ')}"
    doc << "- **Camera entities**: #{camera_entities.count} #{camera_entities.map { |e| e['entity_id'] }.join(', ')}"
    doc << "- **Media players**: #{media_entities.count} #{media_entities.map { |e| e['entity_id'] }.join(', ')}"
    
    # Check for specific sensors we care about
    weather_sensors = sensor_entities.select { |s| s['entity_id'].include?('weather') || s['entity_id'].include?('temperature') || s['entity_id'].include?('humidity') }
    if weather_sensors.any?
      doc << "- **Weather-related sensors**: #{weather_sensors.count}"
      weather_sensors.first(5).each do |sensor|
        doc << "  - #{sensor['entity_id']}: #{sensor['state']} #{sensor.dig('attributes', 'unit_of_measurement')}"
      end
    end
    
    doc << ""
    doc << "## All Entities by Domain"
    doc << ""
    
    # Detailed list by domain
    entities_by_domain.each do |domain, entities|
      doc << "### #{domain.capitalize} (#{entities.count} entities)"
      doc << ""
      
      entities.each do |entity|
        entity_id = entity['entity_id']
        state = entity['state']
        friendly_name = entity.dig('attributes', 'friendly_name') || entity_id
        
        # Highlight important entities
        if entity_id.include?('weather') || entity_id.include?('camera') || entity_id.include?('vision')
          doc << "- **#{entity_id}** - #{friendly_name} (#{state})"
        else
          doc << "- #{entity_id} - #{friendly_name} (#{state})"
        end
        
        # Add important attributes for certain entity types
        if domain == 'sensor' && entity_id.include?('weather')
          attributes = entity['attributes'] || {}
          if attributes['weather_data']
            doc << "  - Has weather_data attribute"
          end
        end
      end
      
      doc << ""
    end
    
    doc << "## Integration Notes"
    doc << ""
    doc << "### Weather Integration"
    doc << "- Primary weather entity: weather.openweathermap"
    doc << "- Weather sensor: sensor.playa_weather_api (template sensor with weather_data)"
    doc << "- Weather summary storage: input_text.current_weather"
    doc << ""
    doc << "### Camera Integration"
    doc << "- Available camera: camera.tablet"
    doc << "- Vision analysis storage: input_text.camera_vision_analysis"
    doc << "- Vision status sensor: sensor.camera_vision_status"
    doc << "- People count sensor: sensor.camera_people_count"
    doc << ""
    doc << "### GPS/Location Integration"
    doc << "- Device tracker: device_tracker.glitch_cube (needs creation)"
    doc << "- Current lat: input_number.glitch_cube_lat"
    doc << "- Current lng: input_number.glitch_cube_lng"
    doc << "- Previous lat: input_number.glitch_cube_prev_lat"
    doc << "- Previous lng: input_number.glitch_cube_prev_lng"
    
    doc.join("\n")
  end

  def print_summary(entities_by_domain)
    puts "\n📊 Entity Summary:"
    puts "  Total domains: #{entities_by_domain.count}"
    puts "  Total entities: #{entities_by_domain.values.flatten.count}"
    
    # Highlight key domains
    %w[weather camera sensor input_text media_player].each do |domain|
      if entities_by_domain[domain]
        puts "  #{domain}: #{entities_by_domain[domain].count} entities"
      end
    end
  end
end

# Run the updater
if __FILE__ == $0
  updater = HAEntitiesDocUpdater.new
  updater.update_documentation
end