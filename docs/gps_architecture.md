# GPS Architecture Documentation

## Overview
The GPS tracking system provides real-time location services for the Glitch Cube art installation at Burning Man. It combines PostGIS spatial queries, geocoding calculations, and Burning Man's unique coordinate system to track the cube's position and proximity to landmarks.

## Core Components

### 1. Location Services

#### GpsTrackingService (`lib/services/gps_tracking_service.rb`)
Primary service for GPS operations and location tracking.

**Key Methods:**
- `current_location` - Returns current GPS coordinates with BRC address
- `proximity_data(lat, lng)` - Analyzes nearby landmarks and distances
- `simulate_movement` - Testing mode for GPS movement simulation

**Features:**
- Real GPS integration via Home Assistant sensors
- Simulation mode using Redis for testing
- Automatic BRC coordinate conversion
- Nearest landmark detection

#### GpsCacheService (`lib/services/gps_cache_service.rb`)
Thread-safe caching layer for GPS operations.

**Key Methods:**
- `cached_location` - 5-second TTL cache for current position
- `cached_proximity(lat, lng)` - Cached proximity calculations
- `cached_landmarks_near(lat, lng, radius)` - 25-second TTL for landmarks

**Features:**
- Thread-safe Mutex synchronization for Puma
- In-memory caching with configurable TTL
- Automatic cache invalidation
- Performance optimization for real-time tracking

### 2. Coordinate Systems

#### BrcCoordinateService (`lib/utils/brc_coordinate_service.rb`)
Converts GPS coordinates to Burning Man's time-and-street addressing.

**Constants:**
- `GOLDEN_SPIKE_COORDS` - Single source of truth for city center (40.78696345, -119.2030071)
- `STREET_DISTANCES` - Real distances from GIS data (Esplanade to Kilgore)

**Key Methods:**
- `brc_address_from_coordinates(lat, lng)` - Converts GPS to "6:30 & Esplanade" format
- `distance_between_points` - Haversine distance calculation
- `bearing_between_points` - Bearing calculation for time streets

**BRC Street System:**
- **Radial Streets:** Clock positions (2:00 to 10:00)
  - 6:00 = 180° (due south)
  - Each hour = 30° of arc
- **Concentric Streets:** Named/lettered rings
  - Esplanade (0.472 miles from center)
  - Through Kilgore (1.09 miles)

### 3. Spatial Database

#### Landmark Model (`app/models/landmark.rb`)
PostGIS-enabled ActiveRecord model for points of interest.

**Spatial Queries:**
- `within_radius(lat, lng, radius_km)` - PostGIS ST_DWithin for proximity
- `by_distance_from(lat, lng)` - Distance-ordered results
- `near_location(lat, lng, radius)` - Combined proximity and active filter

**Features:**
- Automatic PostGIS spatial column updates
- Fallback to geocoder for non-PostGIS environments
- SQL injection protection via connection.quote()
- GeoJSON import for plazas, toilets, art

### 4. Utility Modules

#### LocationHelper (`lib/utils/location_helper.rb`)
General location utilities and calculations.

**Methods:**
- `haversine_distance` - Distance between points
- `calculate_bearing` - Bearing calculations
- `within_trash_fence?` - Perimeter boundary checking
- `point_in_polygon?` - Ray-casting algorithm

#### CoordinateValidator (`lib/utils/coordinate_validator.rb`)
Input validation and sanitization for GPS data.

**Validation:**
- Latitude range: -90 to 90
- Longitude range: -180 to 180
- BRC perimeter bounds checking
- Numeric type validation

## Data Flow

```
GPS Input → CoordinateValidator → GpsCacheService → GpsTrackingService
                                         ↓
                                  BrcCoordinateService
                                         ↓
                                  Landmark Model (PostGIS)
                                         ↓
                                  Response with BRC Address
```

## Security Features

1. **SQL Injection Prevention**
   - All user inputs sanitized with `connection.quote()`
   - Parameterized queries for PostGIS operations

2. **Thread Safety**
   - Mutex synchronization in cache service
   - Safe for concurrent Puma workers

3. **Input Validation**
   - CoordinateValidator for all GPS inputs
   - Range checking and type validation
   - Prevents invalid coordinates from reaching database

## Performance Optimizations

1. **Caching Strategy**
   - 5-second TTL for real-time position
   - 25-second TTL for landmark queries
   - Thread-safe in-memory cache

2. **PostGIS Spatial Indexing**
   - ST_DWithin for efficient radius queries
   - ST_Distance for precise geographic calculations
   - Spatial indexes on location column

3. **Fallback Mechanisms**
   - Geocoder gem when PostGIS unavailable
   - Approximate calculations for testing
   - Graceful degradation

## Configuration

### Environment Variables
```bash
# Home Assistant Integration
HOME_ASSISTANT_URL=http://homeassistant.local:8123
HOME_ASSISTANT_TOKEN=your_token_here

# Redis for simulation mode
REDIS_URL=redis://localhost:6379

# PostGIS Database
DATABASE_URL=postgresql://user:pass@localhost/glitchcube
```

### Constants (`config/constants.rb`)
```ruby
COORDINATES = {
  lat: 40.786958,
  lng: -119.202994,
  lat_lng_string: "40.786958,-119.202994"
}
```

## Testing

### Simulation Mode
```ruby
# Enable simulation in Redis
Services::GpsTrackingService.new.simulate_movement

# Movement patterns available:
# - Random walk within BRC perimeter
# - Circular path around Esplanade
# - Direct path to landmarks
```

### RSpec Tests
```bash
# Run GPS-specific tests
bundle exec rspec spec/services/gps_tracking_service_spec.rb
bundle exec rspec spec/services/gps_cache_service_spec.rb

# Test coordinate calculations
bundle exec rspec spec/utils/brc_coordinate_service_spec.rb
```

## API Endpoints

### GPS Map View
```
GET /gps_map
```
Interactive map showing current position and landmarks.

### Movement API
```
POST /api/v1/movement
{
  "latitude": 40.786958,
  "longitude": -119.202994
}
```
Updates current GPS position.

### GPS Status API
```
GET /api/v1/gps
```
Returns current location with BRC address and nearby landmarks.

## Common Usage Patterns

### Get Current Location with BRC Address
```ruby
service = Services::GpsTrackingService.new
location = service.current_location
# => {
#   latitude: 40.786958,
#   longitude: -119.202994,
#   brc_address: "6:00 & Esplanade",
#   nearest_landmark: "Center Camp",
#   distance_to_landmark: 0.15
# }
```

### Find Nearby Landmarks
```ruby
landmarks = Landmark.near_location(40.786958, -119.202994, 0.5)
# Returns landmarks within 0.5 miles
```

### Convert GPS to BRC Address
```ruby
address = Utils::BrcCoordinateService.brc_address_from_coordinates(
  40.786958, 
  -119.202994
)
# => "6:00 & Esplanade"
```

### Cache GPS Data
```ruby
# Automatically cached for 5 seconds
location = Services::GpsCacheService.cached_location

# Manual cache clear
Services::GpsCacheService.clear_cache!
```

## Troubleshooting

### Common Issues

1. **Incorrect BRC Address**
   - Verify GOLDEN_SPIKE_COORDS matches current year's placement
   - Check bearing calculation (should not have -60° offset)
   - Ensure street distances match GIS data

2. **PostGIS Not Available**
   - System automatically falls back to geocoder
   - Check database migrations: `bundle exec rake db:migrate`
   - Verify PostGIS extension: `SELECT PostGIS_version();`

3. **Cache Not Updating**
   - Default TTL is 5 seconds for position
   - Clear cache manually: `GpsCacheService.clear_cache!`
   - Check Redis connection for simulation mode

4. **Thread Safety Warnings**
   - Ensure Mutex is properly initialized
   - Don't use class variables without synchronization
   - Test with multiple Puma workers

## Maintenance

### Update Street Data
1. Download latest BRC GIS data
2. Run import task: `bundle exec rake import:gis_data`
3. Verify landmarks: `Landmark.count`

### Monitor Performance
```ruby
# Check cache hit rates
Services::LoggerService.log_api_call(
  service: 'gps_cache',
  endpoint: 'cached_location',
  cache_hit: true
)
```

### Database Indexes
```sql
-- Ensure spatial index exists
CREATE INDEX index_landmarks_on_location 
ON landmarks USING GIST (location);

-- Index for type queries
CREATE INDEX index_landmarks_on_landmark_type 
ON landmarks (landmark_type);
```

## Future Enhancements

1. **Predictive Movement**
   - Machine learning for path prediction
   - Anticipatory landmark loading

2. **Offline Mode**
   - Local PostGIS database on Raspberry Pi
   - Sync when connectivity returns

3. **Multi-Year Support**
   - Store historical BRC layouts
   - Dynamic year selection

4. **Advanced Caching**
   - Redis-based distributed cache
   - Geospatial caching strategies