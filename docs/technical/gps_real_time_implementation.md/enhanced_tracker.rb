require 'sinatra'
require 'json'
require 'webrick'

# Configure Sinatra to use WEBrick
configure do
  set :server, :webrick
  set :port, 4567
  set :bind, '0.0.0.0'
  set :public_folder, File.dirname(__FILE__) + '/public'
end

# Enable CORS
before do
  response.headers['Access-Control-Allow-Origin'] = '*'
  response.headers['Access-Control-Allow-Methods'] = 'GET, POST, OPTIONS'
  response.headers['Access-Control-Allow-Headers'] = 'Content-Type'
end

options '*' do
  200
end

# Simple in-memory storage
$current_location = { 
  lat: 40.7712, 
  lng: -119.2030, 
  timestamp: Time.now
}

# Burning Man 2025 approximate locations
BURNING_MAN_CENTER = { lat: 40.7712, lng: -119.2030 }
RENO_LOCATION = { lat: 39.5296, lng: -119.8138 }
AIRPORT_LOCATION = { lat: 40.6622, lng: -119.4341 }

def distance_km(lat1, lng1, lat2, lng2)
  r = 6371
  dlat = (lat2 - lat1) * Math::PI / 180
  dlng = (lng2 - lng1) * Math::PI / 180
  
  a = Math.sin(dlat/2)**2 + Math.cos(lat1 * Math::PI / 180) * 
      Math.cos(lat2 * Math::PI / 180) * Math.sin(dlng/2)**2
  c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
  r * c
end

def get_location_context(lat, lng)
  distance_to_center = distance_km(lat, lng, BURNING_MAN_CENTER[:lat], BURNING_MAN_CENTER[:lng])
  distance_to_reno = distance_km(lat, lng, RENO_LOCATION[:lat], RENO_LOCATION[:lng])
  distance_to_airport = distance_km(lat, lng, AIRPORT_LOCATION[:lat], AIRPORT_LOCATION[:lng])
  
  if distance_to_reno < 20
    return "RENO?!?!"
  elsif distance_to_airport < 5
    return "Airport"
  elsif distance_to_center > 8
    return "Deep Playa"
  elsif distance_to_center > 4
    return "Outer Playa"
  else
    # Calculate approximate intersection using actual street data
    begin
      streets_data = JSON.parse(File.read('street_lines.geojson'))
      
      # Find closest streets (simplified approach)
      radial_streets = []
      concentric_streets = []
      
      streets_data['features'].each do |feature|
        street_type = feature['properties']['type']
        street_name = feature['properties']['name']
        
        # Calculate distance to this street (simplified - just check first coordinate)
        coords = feature['geometry']['coordinates']
        first_coord = coords[0]
        street_distance = distance_km(lat, lng, first_coord[1], first_coord[0]) * 1000 # meters
        
        if street_type == 'radial'
          radial_streets << { name: street_name, distance: street_distance }
        else
          concentric_streets << { name: street_name, distance: street_distance }
        end
      end
      
      # Find closest of each type
      closest_radial = radial_streets.min_by { |s| s[:distance] }
      closest_concentric = concentric_streets.min_by { |s| s[:distance] }
      
      if closest_radial && closest_concentric
        return "#{closest_radial[:name]} & #{closest_concentric[:name]}"
      end
    rescue => e
      puts "Error reading street data: #{e.message}"
    end
    
    # Fallback to approximate calculation
    angle = Math.atan2(lng - BURNING_MAN_CENTER[:lng], lat - BURNING_MAN_CENTER[:lat]) * 180 / Math::PI
    angle = (angle + 360) % 360
    
    time_streets = ["12:00", "12:30", "1:00", "1:30", "2:00", "2:30", "3:00", "3:30", 
                   "4:00", "4:30", "5:00", "5:30", "6:00", "6:30", "7:00", "7:30", 
                   "8:00", "8:30", "9:00", "9:30", "10:00", "10:30", "11:00", "11:30"]
    
    time_index = ((angle / 15).round % 24)
    radial_street = time_streets[time_index]
    
    if distance_to_center < 0.5
      concentric = "Center Camp"
    elsif distance_to_center < 1.0
      concentric = "Rod's Road"
    elsif distance_to_center < 1.5
      concentric = "Esplanade"
    elsif distance_to_center < 2.0
      concentric = "A Street"
    elsif distance_to_center < 2.5
      concentric = "B Street"
    else
      concentric = "C Street"
    end
    
    "#{radial_street} & #{concentric}"
  end
end

# API Routes
get '/api/location' do
  content_type :json
  
  context = get_location_context($current_location[:lat], $current_location[:lng])
  
  {
    lat: $current_location[:lat],
    lng: $current_location[:lng],
    timestamp: $current_location[:timestamp],
    context: context,
    last_updated: Time.now
  }.to_json
end

post '/api/location' do
  data = JSON.parse(request.body.read)
  
  $current_location = {
    lat: data['lat'].to_f,
    lng: data['lng'].to_f,
    timestamp: Time.now
  }
  
  content_type :json
  { status: 'updated', location: $current_location }.to_json
end

# Serve GeoJSON data
get '/api/streets' do
  content_type :json
  begin
    File.read('street_lines.geojson')
  rescue => e
    { error: "Could not load street data: #{e.message}" }.to_json
  end
end

get '/api/toilets' do
  content_type :json
  begin
    File.read('toilets.geojson')
  rescue => e
    { error: "Could not load toilet data: #{e.message}" }.to_json
  end
end

# Simulate movement for demo
get '/api/simulate' do
  $current_location[:lat] += (rand - 0.5) * 0.01
  $current_location[:lng] += (rand - 0.5) * 0.01
  $current_location[:timestamp] = Time.now
  
  redirect '/api/location'
end

get '/' do
  send_file File.join(settings.public_folder, 'index.html')
end

if __FILE__ == $0
  puts "🔥 Enhanced Burning Man Art Cube Tracker starting on http://localhost:4567"
  puts "API endpoints:"
  puts "  GET  /api/location"
  puts "  POST /api/location" 
  puts "  GET  /api/streets"
  puts "  GET  /api/toilets"
  puts "  GET  /api/simulate (for testing)"
end

