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

            # Use cached data for this expensive operation
            result = Services::GisCacheService.cached_streets
            json(result)
          end

          app.get '/api/v1/gis/toilets' do
            content_type :json

            # Use cached data for this expensive operation
            result = Services::GisCacheService.cached_toilets
            json(result)
          end

          app.get '/api/v1/gis/blocks' do
            content_type :json

            # Use cached data for this expensive operation
            result = Services::GisCacheService.cached_city_blocks
            json(result)
          end

          app.get '/api/v1/gis/plazas' do
            content_type :json

            # Use cached data for this expensive operation
            result = Services::GisCacheService.cached_plazas
            json(result)
          end

          # Viewport-based endpoints for progressive loading
          app.get '/api/v1/gis/streets/viewport' do
            content_type :json

            # Get viewport bounds from params
            sw_lng = params[:sw_lng]&.to_f
            sw_lat = params[:sw_lat]&.to_f
            ne_lng = params[:ne_lng]&.to_f
            ne_lat = params[:ne_lat]&.to_f

            if sw_lng && sw_lat && ne_lng && ne_lat
              # Use PostGIS spatial query for viewport
              streets = Street.active
                              .within_viewport(sw_lng, sw_lat, ne_lng, ne_lat)
                              .limit(100) # Limit for performance

              features = streets.map do |street|
                {
                  type: 'Feature',
                  geometry: {
                    type: 'LineString',
                    coordinates: street.coordinates
                  },
                  properties: {
                    id: street.id,
                    name: street.name,
                    street_type: street.street_type,
                    width: street.width
                  }
                }
              end

              json({
                     type: 'FeatureCollection',
                     features: features,
                     count: features.length,
                     source: 'viewport_query'
                   })
            else
              status 400
              json({ error: 'Missing viewport bounds parameters' })
            end
          end

          app.get '/api/v1/gis/landmarks/nearby' do
            content_type :json

            lat = params[:lat]&.to_f
            lng = params[:lng]&.to_f
            radius = (params[:radius] || 1000).to_f # Default 1km radius

            if lat && lng
              # Use PostGIS proximity query
              landmarks = Landmark.within_meters(lng, lat, radius)
                                  .limit(50) # Limit for performance

              features = landmarks.map do |landmark|
                {
                  name: landmark.name,
                  lat: landmark.latitude.to_f,
                  lng: landmark.longitude.to_f,
                  type: landmark.landmark_type,
                  distance: landmark.respond_to?(:distance_meters) ? landmark.distance_meters : nil,
                  description: landmark.description
                }
              end

              json({
                     landmarks: features,
                     count: features.length,
                     center: { lat: lat, lng: lng },
                     radius: radius,
                     source: 'proximity_query'
                   })
            else
              status 400
              json({ error: 'Missing lat/lng parameters' })
            end
          end

          app.get '/api/v1/gis/blocks/viewport' do
            content_type :json

            sw_lng = params[:sw_lng]&.to_f
            sw_lat = params[:sw_lat]&.to_f
            ne_lng = params[:ne_lng]&.to_f
            ne_lat = params[:ne_lat]&.to_f

            if sw_lng && sw_lat && ne_lng && ne_lat
              # Use PostGIS spatial query for viewport
              blocks = Boundary.active
                               .where(boundary_type: 'city_block')
                               .where('geom && ST_MakeEnvelope(?, ?, ?, ?, 4326)', sw_lng, sw_lat, ne_lng, ne_lat)
                               .limit(50) # Limit for performance

              features = blocks.map do |block|
                {
                  type: 'Feature',
                  geometry: {
                    type: 'Polygon',
                    coordinates: block.coordinates
                  },
                  properties: {
                    id: block.id,
                    name: block.name
                  }
                }
              end

              json({
                     type: 'FeatureCollection',
                     features: features,
                     count: features.length,
                     source: 'viewport_query'
                   })
            else
              status 400
              json({ error: 'Missing viewport bounds parameters' })
            end
          end

          # Load everything except toilets - full map view
          app.get '/api/v1/gis/initial' do
            content_type :json

            # Load trash fence and all landmarks except toilets
            fence = Boundary.trash_fence
            all_landmarks = Landmark.active.where.not(landmark_type: 'toilet')

            features = []

            # Add trash fence
            if fence
              features << {
                type: 'Feature',
                geometry: {
                  type: 'Polygon',
                  coordinates: fence.coordinates
                },
                properties: {
                  id: "boundary-#{fence.id}",
                  name: fence.name,
                  feature_type: 'boundary'
                }
              }
            end

            # Add all landmarks (except toilets)
            all_landmarks.each do |landmark|
              feature_type = case landmark.landmark_type
                             when 'center', 'sacred', 'gathering' then 'major_landmark'
                             else 'landmark'
                             end

              features << {
                type: 'Feature',
                geometry: {
                  type: 'Point',
                  coordinates: [landmark.longitude.to_f, landmark.latitude.to_f]
                },
                properties: {
                  id: "landmark-#{landmark.id}",
                  name: landmark.name,
                  feature_type: feature_type,
                  landmark_type: landmark.landmark_type
                }
              }
            end

            json({
                   type: 'FeatureCollection',
                   features: features,
                   count: features.length,
                   source: 'initial_load'
                 })
          end

          app.get '/api/v1/gis/trash_fence' do
            content_type :json

            # Use cached data for this expensive operation
            result = Services::GisCacheService.cached_trash_fence
            json(result)
          end

          # Clear GIS cache endpoint
          app.delete '/api/v1/gis/cache' do
            content_type :json
            success = Services::GisCacheService.clear_cache!
            json({ success: success, message: 'GIS cache cleared' })
          end

          # External map app endpoint - includes location with rich proximity context
          app.get '/api/v1/gps/cube_current_loc' do
            content_type :json

            # Add CORS headers for external app access
            headers 'Access-Control-Allow-Origin' => '*'
            headers 'Access-Control-Allow-Methods' => 'GET'
            headers 'Access-Control-Allow-Headers' => 'Content-Type'

            begin
              # Get current location with full context
              gps_service = ::Services::GpsTrackingService.new
              location = gps_service.current_location

              if location.nil? || !location[:lat] || !location[:lng]
                status 503
                return json({
                              error: 'GPS tracking not available',
                              message: 'No GPS data available',
                              timestamp: Time.now.utc.iso8601
                            })
              end

              # Get proximity context
              lat = location[:lat]
              lng = location[:lng]
              proximity = ::Services::GpsCacheService.cached_proximity(lat, lng)

              # Find nearest intersection/street
              gps_service = ::Services::GpsTrackingService.new
              brc_address = gps_service.brc_address_from_coordinates(lat, lng)

              # Get nearby landmarks
              nearby_landmarks = Landmark.within_meters(lng, lat, 1000)
                                         .limit(10)
                                         .map do |landmark|
                distance = gps_service.haversine_distance(lat, lng, landmark.latitude.to_f, landmark.longitude.to_f)
                {
                  name: landmark.name,
                  type: landmark.landmark_type,
                  distance_meters: distance.round(0),
                  distance_text: distance < 100 ? "#{distance.round(0)}m" : "#{(distance / 1000.0).round(1)}km"
                }
              end
                                         .sort_by { |l| l[:distance_meters] }

              # Response for external app
              response_data = {
                # Core location
                lat: lat,
                lng: lng,
                timestamp: location[:timestamp] || Time.now.utc.iso8601,

                # Context information
                address: brc_address || location[:address],
                context: location[:context],
                section: location[:section],
                distance_from_man: location[:distance_from_man],

                # Proximity data
                nearest_intersection: brc_address,
                nearby_landmarks: nearby_landmarks.take(5),

                # Visual/map context
                map_mode: proximity[:map_mode] || 'normal',
                visual_effects: proximity[:visual_effects] || [],

                # Source info
                source: location[:source] || 'unknown',
                last_update: Time.now.utc.iso8601
              }

              # Add closest landmark for context
              if nearby_landmarks.any?
                closest = nearby_landmarks.first
                response_data[:closest_landmark] = if closest[:distance_meters] < 200 # Very close
                                                     "at #{closest[:name]}"
                                                   elsif closest[:distance_meters] < 500 # Nearby
                                                     "near #{closest[:name]} (#{closest[:distance_text]})"
                                                   else
                                                     "#{closest[:distance_text]} from #{closest[:name]}"
                                                   end
              end

              json(response_data)
            rescue StandardError => e
              ::Services::LoggerService.log_api_call(
                service: 'GPS External API',
                endpoint: '/api/v1/gps/cube_current_loc',
                error: e.message,
                success: false
              )
              status 500
              json({
                     error: 'GPS service error',
                     message: e.message,
                     timestamp: Time.now.utc.iso8601
                   })
            end
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
