# Location Configuration

The Glitch Cube is configured with Black Rock City coordinates and Pacific timezone for internal use. Location information is available for weather APIs and other services but is not included in conversation prompts.

## Configuration

Location constants are defined in `/config/constants.rb`:

### Location Data
```ruby
LOCATION = {
  city: 'Black Rock City',
  state: 'Nevada',
  country: 'USA',
  latitude: 40.7864,
  longitude: -119.2065,
  timezone: 'America/Los_Angeles', # Pacific Time
  timezone_name: 'Pacific Time'
}
```

### Coordinate Formats
```ruby
COORDINATES = {
  lat: 40.7864,
  lng: -119.2065,
  lat_lng: [40.7864, -119.2065],
  lat_lng_string: '40.7864,-119.2065'
}
```

## Timezone Handling

All datetime operations use Pacific Time:
- The system uses `TZInfo` gem for accurate timezone conversions
- Handles PST/PDT transitions automatically
- All timestamps in prompts show Pacific Time

## Usage in System Prompts

The SystemPromptService includes only datetime information (location is internal only):

```
CURRENT DATE AND TIME:
Date: Monday, January 13, 2025
Time: 02:30 PM PST
Unix timestamp: 1736805000
```

## Accessing Location Data

### In Ruby Code
```ruby
# Access location constants
location = GlitchCube::Constants::LOCATION
puts "Installing in #{location[:city]}, #{location[:state]}"

# Get coordinates for API calls
coords = GlitchCube::Constants::COORDINATES
weather_api_url = "https://api.weather.gov/points/#{coords[:lat_lng_string]}"
```

### In Conversation Context
```ruby
conversation = Services::ConversationService.new(
  context: {
    location: "Downtown #{GlitchCube::Constants::LOCATION[:city]}",
    coordinates: GlitchCube::Constants::COORDINATES[:lat_lng_string],
    altitude: 4505 # Reno's elevation in feet
  }
)
```

## Future Weather Integration

The coordinates enable future features:
- Real-time weather data from NOAA/NWS APIs
- Sunrise/sunset calculations
- Local event awareness
- Environmental context for conversations

### Example Weather API Integration
```ruby
# National Weather Service API endpoint for Black Rock Desert
nws_endpoint = "https://api.weather.gov/points/40.7864,-119.2065"

# OpenWeatherMap API call
owm_endpoint = "https://api.openweathermap.org/data/2.5/weather?lat=40.7864&lon=-119.2065"
```

## Black Rock Desert Environment

Black Rock City's unique environment characteristics:
- **Elevation**: ~3,907 feet (1,191 meters)
- **Climate**: High desert, extreme conditions
- **Typical Weather**: 
  - Extreme temperature variations (40°F to 100°F+ in a single day)
  - Dust storms with high winds
  - Near-zero humidity
  - Intense sun exposure
  - Occasional rain can turn playa to mud

These environmental factors can influence:
- Glitch Cube's "mood" responses
- Battery performance considerations
- Environmental sensor readings
- Conversation topics about weather and nature

## Testing with Location

When testing location-aware features:

```ruby
# Mock location constants in specs
stub_const('GlitchCube::Constants::LOCATION', {
  city: 'Black Rock City',
  state: 'Nevada',
  timezone: 'America/Los_Angeles',
  latitude: 40.7864,
  longitude: -119.2065
})

# Mock timezone for consistent tests
allow(TZInfo::Timezone).to receive(:get).with('America/Los_Angeles').and_return(mock_tz)
```

## Configuration Updates

To change the installation location:

1. Update `/config/constants.rb` with new coordinates and timezone
2. Update specs to match new location
3. Adjust any weather or location-specific prompts
4. Test timezone conversions thoroughly