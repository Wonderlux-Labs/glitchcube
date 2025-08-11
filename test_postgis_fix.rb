#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify PostGIS coordinate fix

require_relative 'config/app_dependencies'
require_relative 'app/models/street'
require_relative 'lib/utils/brc_coordinate_service'

puts '=== Testing PostGIS Coordinate Fix ==='
puts

# Test coordinates near The Man (should be in city streets)
test_coordinates = [
  { lat: 40.7875, lng: -119.2030, expected: '6:00 area' },
  { lat: 40.787, lng: -119.1980, expected: '7:30 area' },
  { lat: 40.786, lng: -119.2080, expected: '4:30 area' }
]

test_coordinates.each_with_index do |coord, index|
  puts "--- Test #{index + 1}: #{coord[:expected]} ---"
  puts "Coordinates: #{coord[:lat]}, #{coord[:lng]}"

  # Test PostGIS intersection
  intersection = Street.nearest_intersection(coord[:lat], coord[:lng])
  puts 'PostGIS intersection result:'
  puts "  Radial: #{intersection[:radial]}"
  puts "  Arc: #{intersection[:arc]}"
  puts "  Distances: radial=#{intersection[:radial_distance]&.round(2)}m, arc=#{intersection[:arc_distance]&.round(2)}m"

  # Test mathematical calculation for comparison
  golden_spike = Utils::BrcCoordinateService.golden_spike_coordinates
  manual_distance = Utils::BrcCoordinateService.distance_between_points(
    golden_spike[:lat], golden_spike[:lng], coord[:lat], coord[:lng]
  )
  manual_bearing = Utils::BrcCoordinateService.bearing_between_points(
    golden_spike[:lat], golden_spike[:lng], coord[:lat], coord[:lng]
  )

  puts 'Manual calculation:'
  puts "  Distance: #{manual_distance.round(3)} miles"
  puts "  Bearing: #{manual_bearing.round(1)}°"

  # Test the full address resolution
  address = Utils::BrcCoordinateService.brc_address_from_coordinates(coord[:lat], coord[:lng])
  puts "  Final address: #{address}"
  puts
end

puts '=== Street Count Verification ==='
puts "Total streets: #{Street.count}"
puts "Radial streets: #{Street.radial_streets.count}"
puts "Arc streets: #{Street.arc_streets.count}"
puts

puts '=== Sample Street Names ==='
puts "Radial streets: #{Street.radial_streets.limit(5).pluck(:name).join(', ')}"
puts "Arc streets: #{Street.arc_streets.limit(5).pluck(:name).join(', ')}"
