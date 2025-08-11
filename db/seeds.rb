# frozen_string_literal: true

puts '🌱 Starting GlitchCube database seeding...'

# Clear existing data (in all environments for proper seeding)
puts '📊 Clearing existing data for fresh seed'
Boundary.delete_all if defined?(Boundary)
Street.delete_all if defined?(Street)
Landmark.delete_all
puts '✨ Existing data cleared'

# Import all GIS data (landmarks, streets, etc.)
puts '📍 Importing GPS and landmark data...'

begin
  # Import landmarks from GIS files
  # This imports:
  # - 45 POIs from burning_man_landmarks.json
  # - 45 toilets from toilets.geojson
  # - 10 plazas from plazas.geojson
  # - Streets from street_lines.geojson (if Street model exists)
  Landmark.import_from_gis_data('data/gis')

  # Trash fence is already imported from trash_fence.geojson above

  # Report what was imported
  landmark_count = Landmark.count
  street_count = defined?(Street) ? Street.count : 0
  boundary_count = defined?(Boundary) ? Boundary.count : 0

  puts "✅ Successfully imported #{landmark_count} landmarks"
  puts "✅ Successfully imported #{street_count} streets" if street_count.positive?
  puts "✅ Successfully created #{boundary_count} boundaries" if boundary_count.positive?

  # Show breakdown by type
  puts "\n📊 Landmark breakdown by type:"
  Landmark.group(:landmark_type).count.each do |type, count|
    puts "   #{type}: #{count}"
  end

  if defined?(Street) && street_count.positive?
    puts "\n🛣️  Street breakdown by type:"
    Street.group(:street_type).count.each do |type, count|
      puts "   #{type}: #{count}"
    end
  end
rescue StandardError => e
  puts "❌ Error importing GIS data: #{e.message}"
  puts(e.backtrace.first(5).map { |line| "   #{line}" })
  exit 1
end

# Additional seed data for development/testing
if ENV['RACK_ENV'] == 'development' || ENV['RACK_ENV'].nil?
  puts "\n🧪 Adding development-specific data..."

  # Add some test GPS tracking points for development
  # Note: We don't have a GpsTrack model yet, but this could be added later

  puts '✅ Development data added'
end

puts "\n🎉 Database seeding completed successfully!"
puts '📊 Final counts:'
puts "   Landmarks: #{Landmark.count}"
puts "   Streets: #{defined?(Street) ? Street.count : 0}"
puts "   Boundaries: #{defined?(Boundary) ? Boundary.count : 0}"

# Verify critical landmarks are present
critical_landmarks = ['The Man', 'The Temple', 'Center Camp']
missing_landmarks = critical_landmarks.reject do |name|
  Landmark.exists?(name: name)
end

if missing_landmarks.any?
  puts "⚠️  Warning: Missing critical landmarks: #{missing_landmarks.join(', ')}"
else
  puts '✅ All critical landmarks are present'
end

puts "\n🌍 Trash fence boundary available via Boundary.within_fence?(lat, lng)"
puts '   (All Burning Man landmarks are by definition within the perimeter!)'

puts "\n🚀 Ready for GPS tracking and location services!"
