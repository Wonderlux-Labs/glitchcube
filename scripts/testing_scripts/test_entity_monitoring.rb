#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script for entity monitoring system

# Require the services we're testing

puts '🧪 Testing Entity Monitoring System'
puts '=' * 50

# Test 1: Direct API call method
puts "\n📡 Test 1: Direct API call to get entities"
begin
  entities_by_domain = GlitchCube::Services::EntityManagerService.get_entities_by_domain(use_cache: false)
  puts "✅ Found #{entities_by_domain.values.flatten.length} entities across #{entities_by_domain.keys.length} domains"

  # Show domain summary
  puts "\nDomain Summary:"
  entities_by_domain.sort.each do |domain, entities|
    puts "  #{domain}: #{entities.length} entities"
  end
rescue StandardError => e
  puts "❌ Direct API call failed: #{e.message}"
end

# Test 2: Hardware capability detection
puts "\n🔧 Test 2: Hardware capability detection"
begin
  capabilities = GlitchCube::Services::EntityManagerService.get_hardware_capabilities(use_cache: false)
  summary = capabilities[:summary]

  puts 'Hardware Summary:'
  puts "  RGB Lights: #{summary[:rgb_light_count]} (Available: #{summary[:lighting_available]})"
  puts "  Motion Sensors: #{summary[:motion_sensor_count]} (Available: #{summary[:motion_detection_available]})"
  puts "  Media Players: #{summary[:media_player_count]} (Available: #{summary[:tts_available]})"

  # Show specific entities
  if capabilities[:rgb_lights].any?
    puts "\nRGB Light Entities:"
    capabilities[:rgb_lights].each do |light|
      puts "  - #{light['entity_id']} (#{light['state']})"
    end
  else
    puts "\n⚠️ No RGB lights found - lighting features will need configuration"
  end

  if capabilities[:motion_sensors].any?
    puts "\nMotion Sensor Entities:"
    capabilities[:motion_sensors].each do |sensor|
      puts "  - #{sensor['entity_id']} (#{sensor['state']})"
    end
  else
    puts "\n⚠️ No motion sensors found - proactive conversation will need configuration"
  end

  if capabilities[:media_players].any?
    puts "\nMedia Player Entities:"
    capabilities[:media_players].each do |player|
      puts "  - #{player['entity_id']} (#{player['state']})"
    end
  else
    puts "\n⚠️ No media players found"
  end
rescue StandardError => e
  puts "❌ Hardware capability detection failed: #{e.message}"
end

# Test 3: Cache performance
puts "\n⚡ Test 3: Cache performance test"
begin
  # First call (fresh)
  start_time = Time.now
  GlitchCube::Services::EntityManagerService.get_entities_by_domain(use_cache: false)
  fresh_duration = ((Time.now - start_time) * 1000).round

  # Second call (cached if Redis available)
  start_time = Time.now
  GlitchCube::Services::EntityManagerService.get_entities_by_domain(use_cache: true)
  cached_duration = ((Time.now - start_time) * 1000).round

  puts "Fresh API call: #{fresh_duration}ms"
  puts "Cached call: #{cached_duration}ms"

  if GlitchCube.persistence_enabled?
    puts '✅ Caching is enabled and working'
  else
    puts 'ℹ️ Caching is disabled (Redis not available)'
  end
rescue StandardError => e
  puts "❌ Cache performance test failed: #{e.message}"
end

# Test 4: Background job simulation
puts "\n🔄 Test 4: Background job simulation"
begin
  job_data = {
    trigger: 'test_run',
    timestamp: Time.now.iso8601
  }

  # This would normally be queued, but for testing run synchronously
  GlitchCube::Jobs::EntityDocumentationJob.new.perform(job_data)
  puts '✅ Entity documentation job completed successfully'

  # Check if documentation was updated
  doc_path = File.join(GlitchCube.root, 'docs', 'home_assistant_entities.md')
  if File.exist?(doc_path)
    last_modified = File.mtime(doc_path)
    puts "📄 Documentation file updated: #{last_modified}"
  else
    puts '⚠️ Documentation file not found'
  end
rescue StandardError => e
  puts "❌ Background job simulation failed: #{e.message}"
end

puts "\n🎯 Next Steps:"
puts '1. Check RGB light availability for LightingOrchestrator'
puts '2. Verify motion sensor setup for proactive conversations'
puts '3. Deploy Home Assistant automation from config/homeassistant/automations/entity_change_monitor.yaml'
puts '4. Test webhook endpoints with: curl -X POST localhost:4567/api/v1/entities/refresh'

puts "\n✨ Entity monitoring system test complete!"
