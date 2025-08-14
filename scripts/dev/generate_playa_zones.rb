#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'fileutils'

# Generate GeoJSON boundary files for Burning Man playa zones
# Creates concentric polygons for City, Inner Playa, Mid Playa, and Deep Playa

class PlayaZoneGenerator
  THE_MAN_COORDS = { lat: 40.78696345, lng: -119.2030071 }.freeze

  # Zone radii in miles
  ZONES = {
    city: 0.47,           # Within Esplanade
    inner_playa: 0.70,    # Inner playa extends a bit beyond Esplanade
    mid_playa: 1.0,       # Mid playa boundary
    deep_playa: 1.5       # Deep playa (everything beyond is "way out there")
  }.freeze

  def self.generate_all
    puts '🎯 Generating Burning Man playa zone boundaries...'

    # Create output directory
    output_dir = File.expand_path('../data/boundaries/zones', __dir__)
    FileUtils.mkdir_p(output_dir)

    # Generate each zone as a circle/polygon
    ZONES.each do |zone_name, radius_miles|
      puts "  📍 Generating #{zone_name} boundary (#{radius_miles} miles from The Man)..."

      geojson = generate_zone_polygon(zone_name, radius_miles)

      # Write to file
      filename = File.join(output_dir, "#{zone_name}_boundary.geojson")
      File.write(filename, JSON.pretty_generate(geojson))

      puts "    ✅ Saved to #{filename}"
    end

    # Also generate the "trash fence" approximate boundary (pentagonal)
    puts '  🔲 Generating trash fence boundary...'
    fence_geojson = generate_trash_fence_polygon
    fence_file = File.join(output_dir, 'trash_fence_boundary.geojson')
    File.write(fence_file, JSON.pretty_generate(fence_geojson))
    puts "    ✅ Saved to #{fence_file}"

    puts "\n✨ Zone boundaries generated successfully!"
    puts "\nTo import these into the database, run:"
    puts '  rake db:import:zone_boundaries'
  end

  private

  # Generate a circular polygon around The Man
  def self.generate_zone_polygon(zone_name, radius_miles)
    center_lat = THE_MAN_COORDS[:lat]
    center_lng = THE_MAN_COORDS[:lng]

    # Convert miles to degrees (approximate)
    # 1 degree latitude = ~69 miles
    # 1 degree longitude = ~69 miles * cos(latitude)
    lat_offset = radius_miles / 69.0
    lng_offset = radius_miles / (69.0 * Math.cos(center_lat * Math::PI / 180))

    # Generate circle with 64 points
    points = []
    64.times do |i|
      angle = (i / 64.0) * 2 * Math::PI
      lat = center_lat + (lat_offset * Math.sin(angle))
      lng = center_lng + (lng_offset * Math.cos(angle))
      points << [lng, lat]  # GeoJSON uses [lng, lat] order
    end

    # Close the polygon
    points << points.first

    # Create GeoJSON structure
    {
      type: 'FeatureCollection',
      features: [
        {
          type: 'Feature',
          properties: {
            name: zone_name.to_s.split('_').map(&:capitalize).join(' '),
            boundary_type: 'zone',
            zone_type: zone_name.to_s,
            radius_miles: radius_miles,
            center_lat: center_lat,
            center_lng: center_lng,
            description: "#{zone_name.to_s.split('_').map(&:capitalize).join(' ')} zone boundary (#{radius_miles} miles from The Man)"
          },
          geometry: {
            type: 'Polygon',
            coordinates: [points]
          }
        }
      ]
    }
  end

  # Generate pentagonal trash fence boundary
  # Black Rock City is roughly pentagonal
  def self.generate_trash_fence_polygon
    # Approximate vertices of the pentagon (based on actual BRC layout)
    # These are rough estimates - adjust as needed
    vertices = [
      [-119.2350, 40.7650],  # 9:00 corner
      [-119.1700, 40.7650],  # 3:00 corner
      [-119.1550, 40.7950],  # 12:00 point (apex)
      [-119.1850, 40.8100],  # Deep playa point
      [-119.2200, 40.8100],  # Deep playa point
      [-119.2500, 40.7950],  # Back towards 9:00
      [-119.2350, 40.7650]   # Close polygon
    ]

    {
      type: 'FeatureCollection',
      features: [
        {
          type: 'Feature',
          properties: {
            name: 'Trash Fence Perimeter',
            boundary_type: 'fence',
            description: 'Outer perimeter fence of Black Rock City'
          },
          geometry: {
            type: 'Polygon',
            coordinates: [vertices]
          }
        }
      ]
    }
  end
end

# Run if executed directly
if __FILE__ == $0
  PlayaZoneGenerator.generate_all
end
