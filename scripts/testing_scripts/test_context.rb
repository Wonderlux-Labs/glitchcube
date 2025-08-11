#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'app'

# Test points at various locations
test_locations = [
  { name: 'Center Camp', lat: 40.7864, lng: -119.2065 },
  { name: 'The Man', lat: 40.78696, lng: -119.2030 },
  { name: 'Deep Playa', lat: 40.80, lng: -119.20 },
  { name: '6:00 & Cherryh', lat: 40.7864, lng: -119.213 },
  { name: 'Random art car location', lat: 40.788, lng: -119.205 },
  { name: 'Outside fence', lat: 40.82, lng: -119.20 }
]

puts "=== Testing Location Context Service ===\n\n"

test_locations.each do |loc|
  puts "📍 #{loc[:name]} (#{loc[:lat]}, #{loc[:lng]})"
  puts '-' * 50

  context = Services::LocationContextService.full_context(loc[:lat], loc[:lng])

  puts "Zone: #{context[:zone]}"
  puts "Address: #{context[:address]}"
  puts "Distance from Man: #{context[:distance_from_man]}"
  puts "Within fence: #{context[:within_fence]}"

  if context[:city_block]
    puts "City block: #{context[:city_block][:name]}"
  end

  if context[:intersection][:radial]
    puts "Nearest radial: #{context[:intersection][:radial]} (#{context[:intersection][:radial_distance].round}m away)"
  end

  if context[:intersection][:arc]
    puts "Nearest arc: #{context[:intersection][:arc]} (#{context[:intersection][:arc_distance].round}m away)"
  end

  if context[:landmarks].any?
    puts 'Nearby landmarks:'
    context[:landmarks].each do |lm|
      puts "  - #{lm[:name]} (#{lm[:type]}, #{lm[:distance_meters].round}m)"
    end
  end

  puts "\n"
end

# Test the zone determination with a grid
puts "=== Zone Map Test ===\n"
puts "Testing a grid of points to visualize zones:\n\n"

# Create a simple ASCII map
lat_range = (40.775..40.815).step(0.005)
lng_range = (-119.22..-119.185).step(0.005)

lat_range.each do |lat|
  lng_range.each do |lng|
    zone = Services::LocationContextService.determine_zone(lat, lng)
    char = case zone
           when 'In The City' then 'C'
           when 'Inner Playa' then 'i'
           when 'Mid Playa' then 'm'
           when 'Deep Playa' then 'd'
           when 'Outside Event' then '.'
           else '?'
           end
    print char
  end
  puts
end

puts "\nLegend: C=City, i=Inner Playa, m=Mid Playa, d=Deep Playa, .=Outside"
