#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'app'

puts '=== City Block Analysis ==='
puts "Total city blocks: #{Boundary.where(boundary_type: 'city_block').count}"

# Test different points
test_points = [
  { name: 'Center Camp', lat: 40.7864, lng: -119.2065 },
  { name: 'The Man', lat: 40.78696, lng: -119.2030 },
  { name: 'Random City Point', lat: 40.785, lng: -119.208 }
]

test_points.each do |point|
  puts "\n=== Testing #{point[:name]} (#{point[:lat]}, #{point[:lng]}) ==="

  # Find containing block
  blocks = Boundary.where(boundary_type: 'city_block')
                   .where('ST_Contains(geom, ST_SetSRID(ST_Point(?, ?), 4326))', point[:lng], point[:lat])

  if blocks.any?
    block = blocks.first
    puts "  In block: #{block.name}"
    puts "  Properties: #{block.properties.slice('fid', 'original_properties')}"
  else
    puts '  Not in any city block'
  end

  # Also get the street intersection
  intersection = Street.nearest_intersection(point[:lat], point[:lng])
  puts "  Street intersection: #{intersection[:radial]} & #{intersection[:arc]}"
end

puts "\n=== Sample Block Names ==="
Boundary.where(boundary_type: 'city_block').order(:name).limit(10).each do |b|
  puts "- #{b.name}"
end

puts "\n=== Block Naming Analysis ==="
names = Boundary.where(boundary_type: 'city_block').pluck(:name)
puts "Total blocks: #{names.count}"
puts "Unique names: #{names.uniq.count}"
puts "First few unique: #{names.uniq.sort.first(10).inspect}"

# Check if we can derive street location from block geometry
puts "\n=== Can we get block intersection from geometry? ==="
sample_block = Boundary.where(boundary_type: 'city_block').first
if sample_block
  # Get the centroid of the block
  result = ActiveRecord::Base.connection.execute(
    "SELECT ST_X(ST_Centroid(geom)) as lng, ST_Y(ST_Centroid(geom)) as lat FROM boundaries WHERE id = #{sample_block.id}"
  ).first

  centroid_lat = result['lat']
  centroid_lng = result['lng']

  puts "Sample block: #{sample_block.name}"
  puts "Centroid: #{centroid_lat}, #{centroid_lng}"

  # Get intersection at centroid
  intersection = Street.nearest_intersection(centroid_lat, centroid_lng)
  puts "Intersection at centroid: #{intersection[:radial]} & #{intersection[:arc]}"
end
