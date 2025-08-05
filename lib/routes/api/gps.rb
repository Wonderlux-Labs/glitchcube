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

          app.get '/gps/cube' do
            erb :gps_cube, views: File.expand_path('../../../views', __dir__)
          end

          app.get '/api/v1/gps/location' do
            content_type :json

            require_relative '../../services/gps_tracking_service'
            gps_service = Services::GpsTrackingService.new
            location = gps_service.current_location

            # Add proximity data for map reactions
            if location[:lat] && location[:lng]
              proximity = gps_service.proximity_data(location[:lat], location[:lng])
              location[:proximity] = proximity
            end

            json(location)
          end

          app.get '/api/v1/gps/proximity' do
            content_type :json

            require_relative '../../services/gps_tracking_service'
            gps_service = Services::GpsTrackingService.new
            current_loc = gps_service.current_location

            if current_loc[:lat] && current_loc[:lng]
              proximity = gps_service.proximity_data(current_loc[:lat], current_loc[:lng])
              json(proximity)
            else
              json({ landmarks: [], portos: [], map_mode: 'normal', visual_effects: [] })
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
                  gps_service = Services::GpsTrackingService.new
                  
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
              Services::LoggerService.log_api_call(
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
        end
      end
    end
  end
end