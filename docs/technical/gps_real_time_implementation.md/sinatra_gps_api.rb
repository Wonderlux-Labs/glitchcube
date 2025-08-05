require 'sinatra'
require 'json'
require 'net/http'
require 'uri'

# Enable CORS for frontend integration
before do
  response.headers['Access-Control-Allow-Origin'] = '*'
  response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, DELETE, OPTIONS'
  response.headers['Access-Control-Allow-Headers'] = 'Content-Type, Authorization'
end

options '*' do
  200
end

# In-memory storage for demo (use Redis/database in production)
$current_location = { lat: 40.771, lng: -119.203, timestamp: Time.now }
$location_history = []

# Load Burning Man GIS data
def load_burning_man_gis
  # In production, load from local files or cache
  @street_lines ||= JSON.parse(File.read('street_lines.geojson'))
rescue => e
  puts "Error loading GIS data: #{e.message}"
  @street_lines = { "type" => "FeatureCollection", "features" => [] }
end

# Calculate distance between two points (Haversine formula)
def haversine_distance(lat1, lng1, lat2, lng2)
  r = 6371 # Earth's radius in km
  
  dlat = (lat2 - lat1) * Math::PI / 180
  dlng = (lng2 - lng1) * Math::PI / 180
  
  a = Math.sin(dlat/2) * Math.sin(dlat/2) +
      Math.cos(lat1 * Math::PI / 180) * Math.cos(lat2 * Math::PI / 180) *
      Math.sin(dlng/2) * Math.sin(dlng/2)
  
  c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
  r * c * 1000 # Return distance in meters
end

# Find nearest intersection to current location
def find_nearest_intersection(lat, lng)
  load_burning_man_gis
  
  min_distance = Float::INFINITY
  nearest_intersection = nil
  
  # Simple approach: find closest street intersection
  # In production, use spatial indexing for better performance
  radial_streets = []
  concentric_streets = []
  
  @street_lines['features'].each do |feature|
    street_type = feature['properties']['type']
    street_name = feature['properties']['name']
    
    if street_type == 'radial'
      radial_streets << { name: street_name, feature: feature }
    else
      concentric_streets << { name: street_name, feature: feature }
    end
  end
  
  # Find closest radial and concentric street combination
  closest_radial = radial_streets.min_by do |street|
    coords = street[:feature]['geometry']['coordinates']
    # Calculate distance to street centerline (simplified)
    coords.map { |coord| haversine_distance(lat, lng, coord[1], coord[0]) }.min
  end
  
  closest_concentric = concentric_streets.min_by do |street|
    coords = street[:feature]['geometry']['coordinates']
    coords.map { |coord| haversine_distance(lat, lng, coord[1], coord[0]) }.min
  end
  
  if closest_radial && closest_concentric
    {
      intersection: "#{closest_radial[:name]} & #{closest_concentric[:name]}",
      radial_street: closest_radial[:name],
      concentric_street: closest_concentric[:name],
      estimated_distance: [
        radial_streets.map { |s| s[:feature]['geometry']['coordinates'].map { |c| haversine_distance(lat, lng, c[1], c[0]) }.min }.min,
        concentric_streets.map { |s| s[:feature]['geometry']['coordinates'].map { |c| haversine_distance(lat, lng, c[1], c[0]) }.min }.min
      ].max
    }
  else
    { intersection: "Unknown location", estimated_distance: nil }
  end
end

# API Endpoints

# Get current GPS location
get '/api/gps-location' do
  content_type :json
  $current_location.to_json
end

# Update GPS location (for art cube to post its location)
post '/api/gps-update' do
  data = JSON.parse(request.body.read)
  
  $current_location = {
    lat: data['lat'].to_f,
    lng: data['lng'].to_f,
    timestamp: Time.now,
    battery: data['battery'],
    accuracy: data['accuracy']
  }
  
  # Store in history
  $location_history << $current_location.dup
  $location_history = $location_history.last(100) # Keep last 100 points
  
  content_type :json
  { status: 'success', location: $current_location }.to_json
end

# Get nearest intersection
get '/api/nearest-intersection' do
  lat = params['lat']&.to_f || $current_location[:lat]
  lng = params['lng']&.to_f || $current_location[:lng]
  
  intersection_info = find_nearest_intersection(lat, lng)
  
  content_type :json
  intersection_info.to_json
end

# Serve Burning Man GIS data
get '/api/burning-man-gis' do
  content_type :json
  load_burning_man_gis.to_json
end

# Get location history for path tracking
get '/api/location-history' do
  content_type :json
  $location_history.to_json
end

# Health check
get '/api/health' do
  content_type :json
  { 
    status: 'healthy', 
    timestamp: Time.now,
    current_location: $current_location,
    history_count: $location_history.length
  }.to_json
end

# Serve static files for the web interface
get '/' do
  send_file File.join(settings.public_folder, 'index.html')
end

# Start server
if __FILE__ == $0
  set :port, 4567
  set :bind, '0.0.0.0'
  set :public_folder, File.dirname(__FILE__) + '/public'
  
  puts "Starting Burning Man Art Cube Tracker API on port 4567"
  puts "API endpoints:"
  puts "  GET  /api/gps-location"
  puts "  POST /api/gps-update"
  puts "  GET  /api/nearest-intersection"
  puts "  GET  /api/burning-man-gis"
  puts "  GET  /api/location-history"
  puts "  GET  /api/health"
end

