# frozen_string_literal: true

require 'sinatra'
require 'json'

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
  timestamp: Time.now,
  context: '4:30 & Esplanade'
}

# Burning Man 2025 approximate boundaries and key locations
BURNING_MAN_CENTER = { lat: 40.7712, lng: -119.2030 }.freeze
RENO_LOCATION = { lat: 39.5296, lng: -119.8138 }.freeze
AIRPORT_LOCATION = { lat: 40.6622, lng: -119.4341 }.freeze # Black Rock City Airport

def distance_km(lat1, lng1, lat2, lng2)
  r = 6371
  dlat = (lat2 - lat1) * Math::PI / 180
  dlng = (lng2 - lng1) * Math::PI / 180

  a = (Math.sin(dlat / 2)**2) + (Math.cos(lat1 * Math::PI / 180) *
                            Math.cos(lat2 * Math::PI / 180) * (Math.sin(dlng / 2)**2))
  c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
  r * c
end

def get_location_context(lat, lng)
  # Distance from Burning Man center
  distance_to_center = distance_km(lat, lng, BURNING_MAN_CENTER[:lat], BURNING_MAN_CENTER[:lng])
  distance_to_reno = distance_km(lat, lng, RENO_LOCATION[:lat], RENO_LOCATION[:lng])
  distance_to_airport = distance_km(lat, lng, AIRPORT_LOCATION[:lat], AIRPORT_LOCATION[:lng])

  # Determine context based on location
  if distance_to_reno < 20
    'RENO?!?!'
  elsif distance_to_airport < 5
    'Airport'
  elsif distance_to_center > 8
    'Deep Playa'
  elsif distance_to_center > 4
    'Outer Playa'
  else
    # Try to determine intersection (simplified)
    # This is a basic approximation - in reality you'd use the GeoJSON data
    angle = Math.atan2(lng - BURNING_MAN_CENTER[:lng], lat - BURNING_MAN_CENTER[:lat]) * 180 / Math::PI
    angle = (angle + 360) % 360

    # Convert angle to clock position (Burning Man uses clock positions)
    clock_hour = ((angle + 15) / 30).floor + 6 # Adjust for BM orientation
    clock_hour -= 12 if clock_hour > 12
    clock_hour.zero? ? 12 : clock_hour

    # Determine radial street (time-based)
    time_streets = ['12:00', '12:30', '1:00', '1:30', '2:00', '2:30', '3:00', '3:30',
                    '4:00', '4:30', '5:00', '5:30', '6:00', '6:30', '7:00', '7:30',
                    '8:00', '8:30', '9:00', '9:30', '10:00', '10:30', '11:00', '11:30']

    time_index = ((angle / 15).round % 24)
    radial_street = time_streets[time_index]

    # Determine concentric street based on distance
    concentric = if distance_to_center < 0.5
                   'Center Camp'
                 elsif distance_to_center < 1.0
                   "Rod's Road"
                 elsif distance_to_center < 1.5
                   'Esplanade'
                 elsif distance_to_center < 2.0
                   'A Street'
                 elsif distance_to_center < 2.5
                   'B Street'
                 elsif distance_to_center < 3.0
                   'C Street'
                 else
                   'Outer Streets'
                 end

    "#{radial_street} & #{concentric}"
  end
end

# Get current location with context
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

# Update location (for the art cube to post its GPS)
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

# Simulate movement for demo
get '/api/simulate' do
  # Move randomly around the playa
  $current_location[:lat] += (rand - 0.5) * 0.01
  $current_location[:lng] += (rand - 0.5) * 0.01
  $current_location[:timestamp] = Time.now

  redirect '/api/location'
end

# Serve the main page
get '/' do
  send_file File.join(settings.public_folder, 'index.html')
end

if __FILE__ == $PROGRAM_NAME
  set :port, 4567
  set :bind, '0.0.0.0'
  set :public_folder, "#{File.dirname(__FILE__)}/public"

  puts '🔥 Burning Man Art Cube Tracker running on http://localhost:4567'
  puts 'API: GET /api/location, POST /api/location'
end
