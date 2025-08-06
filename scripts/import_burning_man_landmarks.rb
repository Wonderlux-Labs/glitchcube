#!/usr/bin/env ruby
# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

class BurningManLandmarkImporter
  CPNS_URL = 'https://raw.githubusercontent.com/burningmantech/innovate-GIS-data/master/2025/GeoJSON/cpns.geojson'
  OUTPUT_FILE = File.expand_path('../data/gis/burning_man_landmarks.json', __dir__)
  
  def self.import!
    new.import!
  end
  
  def import!
    puts "🔥 Importing Burning Man 2025 landmarks from official GIS data..."
    
    # Fetch the GeoJSON data
    geojson_data = fetch_cpns_data
    landmarks = parse_landmarks(geojson_data)
    
    puts "📍 Found #{landmarks.length} landmarks:"
    landmarks.each do |landmark|
      puts "   #{landmark[:name]} (#{landmark[:type]})"
    end
    
    # Save to file
    save_landmarks(landmarks)
    
    puts "✅ Landmarks saved to #{OUTPUT_FILE}"
    puts "🎯 You can now update your GPS service to use these official coordinates!"
  end
  
  private
  
  def fetch_cpns_data
    uri = URI(CPNS_URL)
    response = Net::HTTP.get_response(uri)
    
    unless response.is_a?(Net::HTTPSuccess)
      raise "Failed to fetch CPNS data: #{response.code} #{response.message}"
    end
    
    JSON.parse(response.body)
  rescue StandardError => e
    puts "❌ Error fetching data: #{e.message}"
    exit 1
  end
  
  def parse_landmarks(geojson_data)
    landmarks = []
    
    geojson_data['features'].each do |feature|
      properties = feature['properties']
      coordinates = feature['geometry']['coordinates']
      
      # GeoJSON uses [lng, lat] format
      lng = coordinates[0]
      lat = coordinates[1]
      
      landmark = {
        name: properties['NAME'] || properties['Name'] || properties['name'] || 'Unknown',
        lat: lat,
        lng: lng,
        type: determine_type(properties),
        alias: properties['ALIAS1'],
        cpn_type: properties['TYPE'],
        icon: determine_icon(properties),
        radius: determine_radius(properties),
        context: generate_context(properties)
      }.compact
      
      landmarks << landmark
    end
    
    # Sort by importance/type
    landmarks.sort_by { |l| type_priority(l[:type]) }
  end
  
  def determine_type(properties)
    name = (properties['NAME'] || properties['Name'] || properties['name'] || '').downcase
    cpn_type = (properties['TYPE'] || '').downcase
    
    case name
    when /temple/i
      'sacred'
    when /the man/i, /man base/i
      'center'
    when /camp/i
      'gathering'
    when /medical/i, /ranger/i, /emergency/i
      'medical'
    when /airport/i, /airfield/i
      'transport'
    when /gate/i, /entrance/i, /exodus/i
      'entrance'
    when /artica/i, /ice/i
      'service'
    when /art/i
      'art'
    when /radio/i, /communication/i
      'communication'
    else
      'poi' # point of interest
    end
  end
  
  def determine_icon(properties)
    name = (properties['NAME'] || properties['Name'] || properties['name'] || '').downcase
    
    case determine_type(properties)
    when 'sacred'
      '🏛️'
    when 'center'
      '🔥'
    when 'gathering'
      '🏕️'
    when 'medical'
      '🚑'
    when 'transport'
      '✈️'
    when 'entrance'
      '🚪'
    when 'service'
      '❄️'
    when 'art'
      '🎨'
    when 'communication'
      '📻'
    else
      '📍'
    end
  end
  
  def determine_radius(properties)
    case determine_type(properties)
    when 'sacred', 'center'
      20 # meters - important landmarks
    when 'medical', 'entrance'
      100 # meters - service areas
    when 'gathering'
      50 # meters - camps
    else
      30 # meters - general POI
    end
  end
  
  def generate_context(properties)
    name = properties['NAME'] || properties['Name'] || properties['name']
    type = determine_type(properties)
    
    case type
    when 'sacred'
      "Approaching #{name} 🏛️"
    when 'center'
      "Near #{name} 🔥"
    when 'gathering'
      "At #{name} 🏕️"
    when 'medical'
      "Near #{name} 🚑"
    when 'transport'
      "#{name} ✈️"
    when 'service'
      "Near #{name}"
    else
      "Near #{name}"
    end
  end
  
  def type_priority(type)
    priorities = {
      'center' => 1,
      'sacred' => 2,
      'gathering' => 3,
      'medical' => 4,
      'entrance' => 5,
      'transport' => 6,
      'service' => 7,
      'art' => 8,
      'communication' => 9,
      'poi' => 10
    }
    priorities[type] || 99
  end
  
  def save_landmarks(landmarks)
    # Ensure directory exists
    dir = File.dirname(OUTPUT_FILE)
    Dir.mkdir(dir) unless Dir.exist?(dir)
    
    output = {
      source: 'Burning Man Innovate GIS Data 2025',
      url: CPNS_URL,
      generated_at: Time.now.utc.iso8601,
      count: landmarks.length,
      landmarks: landmarks
    }
    
    File.write(OUTPUT_FILE, JSON.pretty_generate(output))
  end
end

# Run the import if this script is executed directly
if __FILE__ == $PROGRAM_NAME
  BurningManLandmarkImporter.import!
end