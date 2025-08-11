# frozen_string_literal: true

require './config/environment'

puts '=== PostGIS Street Data Debug ==='

# Check if we have any streets at all
total_streets = Street.count
puts "Total streets in database: #{total_streets}"

if total_streets.positive?
  # Get a sample of streets
  puts "\nSample street data:"
  Street.limit(5).each do |street|
    puts "- #{street.name} (#{street.street_type})"
  end

  # Check specific streets we're interested in
  test_streets = ['6:00', '7:30', 'Esplanade']
  puts "\nLooking for test streets:"
  test_streets.each do |street_name|
    street = Street.find_by(name: street_name)
    if street
      puts "✓ Found #{street_name} (#{street.street_type})"

      # Try to get geometry info
      begin
        result = ActiveRecord::Base.connection.execute(
          "SELECT ST_SRID(geom) as srid, ST_AsText(ST_Centroid(geom)) as center FROM streets WHERE name = '#{street_name}' LIMIT 1"
        )
        if result.first
          puts "  SRID: #{result.first['srid']}"
          puts "  Center: #{result.first['center']}"
        end
      rescue StandardError => e
        puts "  Error getting geometry: #{e.message}"
      end
    else
      puts "✗ Missing #{street_name}"
    end
  end

  # Test the nearest intersection method
  puts "\n=== Testing nearest intersection method ==="
  test_lat = 40.78267764
  test_lng = -119.20758624
  puts "Test coordinates: #{test_lat}, #{test_lng}"

  begin
    result = Street.nearest_intersection(test_lat, test_lng)
    puts "Nearest intersection result: #{result.inspect}"
  rescue StandardError => e
    puts "Error in nearest_intersection: #{e.message}"
    puts e.backtrace.first(5)
  end

else
  puts 'No streets found in database!'
end
