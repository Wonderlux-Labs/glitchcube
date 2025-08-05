# 🔥 Burning Man Art Cube Tracker

Real-time GPS tracking system for autonomous art at Burning Man 2025.

## Quick Start

1. **Install Ruby and dependencies:**
```bash
sudo apt install ruby ruby-dev
sudo gem install sinatra rackup
```

2. **Download Burning Man GIS data:**
```bash
wget -O street_lines.geojson "https://raw.githubusercontent.com/burningmantech/innovate-GIS-data/refs/heads/master/2025/GeoJSON/street_lines.geojson"
wget -O toilets.geojson "https://raw.githubusercontent.com/burningmantech/innovate-GIS-data/refs/heads/master/2025/GeoJSON/toilets.geojson"
```

3. **Start the server:**
```bash
ruby enhanced_tracker.rb
```

4. **Open your browser:**
Navigate to `http://localhost:4567`

## Features

- ✅ Real-time GPS location tracking
- ✅ Burning Man street grid overlay
- ✅ Porto/toilet location markers  
- ✅ Contextual location descriptions ("4:30 & Kilgore", "Deep Playa", etc.)
- ✅ Mobile-responsive interface
- ✅ Free and open source (Leaflet + OpenStreetMap)

## API Endpoints

- `GET /api/location` - Get current location with context
- `POST /api/location` - Update GPS position
- `GET /api/streets` - Get street grid GeoJSON
- `GET /api/toilets` - Get porto locations GeoJSON
- `GET /api/simulate` - Simulate movement (testing)

## GPS Integration

Update location via HTTP POST:
```bash
curl -X POST http://localhost:4567/api/location \
  -H "Content-Type: application/json" \
  -d '{"lat": 40.7712, "lng": -119.2030}'
```

## Files

- `enhanced_tracker.rb` - Main Sinatra server
- `public/index.html` - Frontend web interface
- `street_lines.geojson` - Burning Man street data
- `toilets.geojson` - Porto location data

## Testing

Press 's' key in the web interface to simulate movement and test location context updates.

---

**Ready for the playa! 🎨🔥**

