# frozen_string_literal: true

module GlitchCube
  module Routes
    module Api
      module Gps
        def self.registered(app)
          # GPS Tracking Routes
          app.get '/gps' do
            erb :gps_map, views: File.expand_path('../../../views', __dir__)
          end

          # Simple coords endpoint - just lat/lng
          app.get '/api/v1/gps/coords' do
            location = ::Services::GpsCacheService.cached_location

            if location&.dig(:lat) && location[:lng]
              json({
                     lat: location[:lat],
                     lng: location[:lng]
                   })
            else
              status 503
              json({ error: 'No GPS coordinates available' })
            end
          rescue StandardError => e
            ::Services::LoggerService.log_api_call(
              service: 'GPS API',
              endpoint: '/api/v1/gps/coords',
              error: e.message,
              success: false
            )
            status 500
            json({ error: 'GPS coords error', details: e.message })
          end

          app.get '/api/v1/gps/location' do
            content_type :json

            require_relative '../../services/gps_cache_service'

            begin
              # Use cached location data (1-minute TTL)
              location = ::Services::GpsCacheService.cached_location

              if location.nil?
                status 503 # Service Unavailable
                json({
                       error: 'GPS tracking not available',
                       message: 'No GPS data - simulation not running and no Home Assistant connection',
                       timestamp: Time.now.utc.iso8601
                     })
              else
                # Add cached proximity data for map reactions
                if location[:lat] && location[:lng]
                  proximity = ::Services::GpsCacheService.cached_proximity(location[:lat], location[:lng])
                  location[:proximity] = proximity
                end

                json(location)
              end
            rescue StandardError => e
              status 500
              json({
                     error: 'GPS service error',
                     message: e.message,
                     timestamp: Time.now.utc.iso8601
                   })
            end
          end

          app.get '/api/v1/gps/proximity' do
            content_type :json

            begin
              # Use cached location data
              current_loc = ::Services::GpsCacheService.cached_location

              if current_loc && current_loc[:lat] && current_loc[:lng]
                proximity = ::Services::GpsCacheService.cached_proximity(current_loc[:lat], current_loc[:lng])
                json(proximity)
              else
                json({ landmarks: [], portos: [], map_mode: 'normal', visual_effects: [] })
              end
            rescue StandardError => e
              json({
                     landmarks: [],
                     portos: [],
                     map_mode: 'normal',
                     visual_effects: [],
                     error: e.message
                   })
            end
          end

          app.get '/api/v1/gps/home' do
            content_type :json

            require_relative '../../cube/settings'
            home_coords = Cube::Settings.home_camp_coordinates
            json(home_coords)
          end

          app.get '/api/v1/gps/history' do
            content_type :json

            begin
              # Check if we're in simulation mode
              if Cube::Settings.simulate_cube_movement?
                # Load simulated history
                history_file = File.expand_path('../../../data/simulation/route_history.json', __dir__)
                if File.exist?(history_file)
                  history_data = JSON.parse(File.read(history_file))

                  # Format history for display
                  require_relative '../../services/gps_tracking_service'
                  gps_service = ::Services::GpsTrackingService.new

                  formatted_history = history_data.map do |point|
                    address = gps_service.brc_address_from_coordinates(point['lat'], point['lng'])
                    {
                      lat: point['lat'],
                      lng: point['lng'],
                      timestamp: point['timestamp'],
                      address: address,
                      destination: point['destination']
                    }
                  end

                  json({ history: formatted_history, total_points: formatted_history.length, mode: 'simulated' })
                else
                  # No history file yet
                  json({ history: [], total_points: 0, mode: 'simulated', message: 'No history yet - start simulation' })
                end
              else
                # TODO: Real HA integration for history
                # For now, return sample data
                history = [
                  {
                    lat: 40.7712,
                    lng: -119.2030,
                    timestamp: (Time.now - 3600).iso8601,
                    address: '6:00 & Esplanade'
                  },
                  {
                    lat: 40.7720,
                    lng: -119.2025,
                    timestamp: (Time.now - 1800).iso8601,
                    address: '5:30 & Atwood'
                  }
                ]

                json({ history: history, total_points: history.length, mode: 'sample' })
              end
            rescue StandardError => e
              ::Services::LoggerService.log_api_call(
                service: 'GPS History',
                endpoint: '/api/v1/gps/history',
                error: e.message,
                success: false
              )
              json({ error: 'Unable to fetch GPS history', history: [], total_points: 0 })
            end
          end

          # GeoJSON data endpoints for map overlay
          app.get '/api/v1/gis/streets' do
            content_type :json
            send_file File.join(settings.root, 'data/gis/street_lines.geojson')
          end

          app.get '/api/v1/gis/toilets' do
            content_type :json
            send_file File.join(settings.root, 'data/gis/toilets.geojson')
          end

          app.get '/api/v1/gis/blocks' do
            content_type :json
            send_file File.join(settings.root, 'data/gis/city_blocks.geojson')
          end

          app.get '/api/v1/gis/plazas' do
            content_type :json
            send_file File.join(settings.root, 'data/gis/plazas.geojson')
          end

          app.get '/api/v1/gis/trash_fence' do
            content_type :json
            send_file File.join(settings.root, 'data/gis/trash_fence.geojson')
          end

          app.get '/api/v1/gps/landmarks' do
            content_type :json

            # Cache landmarks forever - they don't move
            headers 'Cache-Control' => 'public, max-age=31536000' # 1 year
            headers 'Expires' => (Time.now + 31_536_000).httpdate

            begin
              # Load all landmarks from database (cacheable since they don't move)
              landmarks = Landmark.active.order(:name).map do |landmark|
                {
                  name: landmark.name,
                  lat: landmark.latitude.to_f,
                  lng: landmark.longitude.to_f,
                  type: landmark.landmark_type,
                  priority: case landmark.landmark_type
                            when 'center', 'sacred' then 1 # Highest priority for Man, Temple
                            when 'medical', 'ranger' then 2  # High priority for emergency services
                            when 'service', 'toilet' then 3  # Medium priority for utilities
                            when 'art' then 4 # Lower priority for art
                            else 5 # Lowest priority for other landmarks
                            end,
                  description: landmark.description || landmark.name
                }
              end

              json({
                     landmarks: landmarks,
                     count: landmarks.length,
                     source: 'Database (Burning Man Innovate GIS Data 2025)',
                     cache_hint: 'forever' # Landmarks don't move, safe to cache indefinitely
                   })
            rescue StandardError => e
              # Fallback to hardcoded landmarks if database unavailable
              require_relative '../../utils/burning_man_landmarks'
              landmarks = Utils::BurningManLandmarks.all_landmarks

              json({
                     landmarks: landmarks,
                     count: landmarks.length,
                     source: 'Fallback (hardcoded)',
                     error: "Database unavailable: #{e.message}"
                   })
            end
          end
        end
      end
    end
  end
end
