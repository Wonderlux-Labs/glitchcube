# Burning Man 2025 GIS Data Analysis

## Available GIS Data Files

From the GitHub repository: https://github.com/burningmantech/innovate-GIS-data/tree/master/2025/GeoJSON

### Key Files for Tracking System:
- **street_lines.geojson** - Street centerlines (essential for intersection detection)
- **street_outlines.geojson** - Street boundaries/outlines
- **city_blocks.geojson** - City block boundaries
- **plazas.geojson** - Plaza locations
- **cpns.geojson** - Center camp and other structures
- **toilets.geojson** - Toilet locations
- **trash_fence.geojson** - Perimeter fence

## Analysis Progress:
- [x] Identified available GeoJSON files
- [ ] Examine street_lines.geojson structure
- [ ] Examine coordinate system used
- [ ] Research Home Assistant device tracker integration
- [ ] Research standalone mapping solutions



## GeoJSON Data Structure Analysis

### Street Lines (street_lines.geojson):
- **Format**: FeatureCollection with 599 LineString features
- **Coordinate System**: WGS84 (standard latitude/longitude)
- **Sample Coordinates**: Around -119.203° longitude, 40.771° latitude (Nevada)
- **Properties**: Each feature has FID, name, width, and type
- **Street Types**: 
  - Radial streets: Named by time (e.g., "4:30", "4:45", "5:00")
  - Concentric streets: Named streets (e.g., "Kilgore")
- **Street Width**: Specified in properties (e.g., "40" feet)

### Key Insights for Tracking System:
1. **Intersection Detection**: Can be calculated using radial/concentric street intersections
2. **Coordinate System**: Standard WGS84 makes it compatible with GPS devices
3. **Street Naming**: Follows Burning Man convention (time + named streets)
4. **Data Quality**: Well-structured with consistent properties

## Next Steps:
- [x] Analyze GeoJSON structure
- [ ] Research Home Assistant device tracker
- [ ] Research standalone mapping solutions
- [ ] Develop prototypes


## Home Assistant Integration Research

### Native Home Assistant Capabilities:
1. **Device Tracker Integration**:
   - Supports GPS-based location tracking
   - Can use `device_tracker.see` action to manually update device locations
   - Accepts GPS coordinates: `[latitude, longitude]`
   - Supports battery level and GPS accuracy reporting
   - Multiple device trackers can work in parallel

2. **Standard Map Card**:
   - Basic mapping functionality with zones and entities
   - Shows device tracker entities as markers
   - Supports path history with `hours_to_show` parameter
   - Limited to basic OpenStreetMap tiles
   - No support for custom GeoJSON overlays

### Advanced Solution: Custom Map Card (nathan-gs/ha-map-card)
**Key Features for Burning Man Project**:
- **WMS Layers**: Support for Web Map Service layers
- **Tile Layers**: Custom tile layer support
- **Custom Tile URLs**: Dynamic tile URLs with entity lookups
- **GeoJSON Support**: Through WMS or tile layers
- **History Tracking**: Path history with customizable time ranges
- **Entity Display Options**: Markers, icons, states, attributes

**Configuration Options**:
```yaml
type: custom:map-card
x: longitude
y: latitude
entities: []
wms: []  # WMS Layers array
tile_layers: []  # Tile Layers array
tile_layer_url: "custom_url/{z}/{x}/{y}.png"
```

### Potential Implementation Approaches:
1. **WMS Server**: Host Burning Man GIS data as WMS service
2. **Tile Server**: Convert GeoJSON to map tiles
3. **Direct GeoJSON**: Use tile layer with GeoJSON overlay
4. **Hybrid**: Combine device tracker with custom map layers



## Standalone HTML/JS Mapping Solutions Research

### Mapbox GL JS Solution:
**Key Features**:
- **Real-time Updates**: Uses `setInterval` + `map.getSource().setData()` for live tracking
- **GeoJSON Support**: Native support for GeoJSON overlays
- **Custom Styling**: Full control over map appearance and layers
- **Performance**: Hardware-accelerated rendering

**Implementation Pattern**:
```javascript
// Real-time GPS tracking
const updateLocation = setInterval(async () => {
    const response = await fetch('/api/gps-location');
    const {latitude, longitude} = await response.json();
    
    const geojson = {
        type: 'FeatureCollection',
        features: [{
            type: 'Feature',
            geometry: {
                type: 'Point',
                coordinates: [longitude, latitude]
            }
        }]
    };
    
    map.getSource('tracker').setData(geojson);
}, 2000);
```

### Leaflet + Leaflet-Realtime Solution:
**Key Features**:
- **Realtime Plugin**: `L.realtime()` for automatic data updates
- **Lightweight**: Smaller bundle size than Mapbox
- **Plugin Ecosystem**: Extensive plugin library
- **GeoJSON Native**: Built-in GeoJSON support

**Implementation Pattern**:
```javascript
const realtime = L.realtime({
    url: '/api/gps-location',
    crossOrigin: true,
    type: 'json'
}, {
    interval: 3000
}).addTo(map);
```

### Intersection Detection Libraries:
1. **Turf.js**: `@turf/line-intersect` for calculating street intersections
2. **Spatial Indexing**: For efficient nearest neighbor searches
3. **Custom Algorithms**: Point-to-line distance calculations

## Sinatra Backend Integration

### NEW: Sinatra App Advantages:
✅ **Backend API**: Can process GPS data and calculate intersections server-side
✅ **GIS Processing**: Handle complex spatial calculations in Ruby
✅ **Data Serving**: Serve Burning Man GeoJSON data efficiently
✅ **Real-time Endpoints**: WebSocket or polling endpoints for live updates
✅ **Intersection API**: Pre-calculate or real-time intersection detection

### Recommended Architecture with Sinatra:
```
Art Cube GPS → Sinatra API → Frontend Map Display
                    ↓
              GIS Data Processing
              Intersection Detection
              Nearest Street Calculation
```

### API Endpoints Needed:
- `GET /api/gps-location` - Current GPS position
- `POST /api/gps-update` - Update GPS position
- `GET /api/nearest-intersection` - Get nearest intersection
- `GET /api/burning-man-gis` - Serve GIS data
- `WebSocket /ws/live-tracking` - Real-time updates

