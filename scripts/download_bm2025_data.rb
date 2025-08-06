#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/http'
require 'json'
require 'fileutils'

# Create data/gis directory
data_dir = File.expand_path('../data/gis', __dir__)
FileUtils.mkdir_p(data_dir)

# BM 2025 GeoJSON files from official repo
base_url = 'https://raw.githubusercontent.com/burningmantech/innovate-GIS-data/master/2025/GeoJSON'
files = [
  'city_blocks.geojson',
  'cpns.geojson', 
  'plazas.geojson',
  'street_lines.geojson',
  'street_outlines.geojson',
  'toilets.geojson',
  'trash_fence.geojson'
]

puts "🔥 Downloading Burning Man 2025 GIS data..."

files.each do |filename|
  url = "#{base_url}/#{filename}"
  output_path = File.join(data_dir, filename)
  
  begin
    puts "  Downloading #{filename}..."
    
    uri = URI(url)
    response = Net::HTTP.get_response(uri)
    
    if response.code == '200'
      File.write(output_path, response.body)
      
      # Validate JSON
      JSON.parse(response.body)
      
      puts "  ✅ #{filename} downloaded successfully"
    else
      puts "  ❌ Failed to download #{filename}: HTTP #{response.code}"
    end
    
  rescue JSON::ParserError => e
    puts "  ⚠️  #{filename} downloaded but invalid JSON: #{e.message}"
  rescue StandardError => e
    puts "  ❌ Error downloading #{filename}: #{e.message}"
  end
end

puts "\n🎯 Download complete! Files saved to: #{data_dir}"
puts "Run this script with: bundle exec ruby scripts/download_bm2025_data.rb"