# frozen_string_literal: true

require 'redis'
require 'json'

module Services
  class GisCacheService
    CACHE_TTL = 86_400 # 24 hours - these don't change during the event
    REDIS_URL = ENV['REDIS_URL'] || 'redis://localhost:6379/0'

    class << self
      def cached_streets
        cache_key = 'gis:streets:all'

        cached = redis.get(cache_key)
        return JSON.parse(cached) if cached

        # Generate and cache the data
        streets = Street.active.map do |street|
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
              width: street.width,
              active: street.active
            }
          }
        end

        result = {
          type: 'FeatureCollection',
          features: streets,
          count: streets.length,
          source: 'database',
          cached_at: Time.now.iso8601
        }

        redis.setex(cache_key, CACHE_TTL, JSON.generate(result))
        result
      rescue StandardError => e
        Services::LoggerService.log_api_call(
          service: 'GIS Cache',
          endpoint: 'cached_streets',
          error: e.message,
          success: false
        )
        # Fallback to direct query if Redis fails
        generate_streets_geojson
      end

      def cached_toilets
        cache_key = 'gis:toilets:all'

        cached = redis.get(cache_key)
        return JSON.parse(cached) if cached

        toilets = Landmark.active.where(landmark_type: 'toilet').map do |toilet|
          {
            type: 'Feature',
            geometry: {
              type: 'Point',
              coordinates: [toilet.longitude.to_f, toilet.latitude.to_f]
            },
            properties: {
              id: toilet.id,
              name: toilet.name,
              description: toilet.description
            }
          }
        end

        result = {
          type: 'FeatureCollection',
          features: toilets,
          count: toilets.length,
          source: 'database',
          cached_at: Time.now.iso8601
        }

        redis.setex(cache_key, CACHE_TTL, JSON.generate(result))
        result
      rescue StandardError => e
        Services::LoggerService.log_api_call(
          service: 'GIS Cache',
          endpoint: 'cached_toilets',
          error: e.message,
          success: false
        )
        generate_toilets_geojson
      end

      def cached_city_blocks
        cache_key = 'gis:blocks:all'

        cached = redis.get(cache_key)
        return JSON.parse(cached) if cached

        blocks = Boundary.active.where(boundary_type: 'city_block').map do |block|
          {
            type: 'Feature',
            geometry: {
              type: 'Polygon',
              coordinates: block.coordinates
            },
            properties: {
              id: block.id,
              name: block.name,
              active: block.active
            }
          }
        end

        result = {
          type: 'FeatureCollection',
          features: blocks,
          count: blocks.length,
          source: 'database',
          cached_at: Time.now.iso8601
        }

        redis.setex(cache_key, CACHE_TTL, JSON.generate(result))
        result
      rescue StandardError => e
        Services::LoggerService.log_api_call(
          service: 'GIS Cache',
          endpoint: 'cached_city_blocks',
          error: e.message,
          success: false
        )
        generate_blocks_geojson
      end

      def cached_plazas
        cache_key = 'gis:plazas:all'

        cached = redis.get(cache_key)
        return JSON.parse(cached) if cached

        plazas = Landmark.active.where(landmark_type: 'plaza').map do |plaza|
          {
            type: 'Feature',
            geometry: {
              type: 'Point',
              coordinates: [plaza.longitude.to_f, plaza.latitude.to_f]
            },
            properties: {
              id: plaza.id,
              name: plaza.name,
              description: plaza.description,
              radius: plaza.radius_meters
            }
          }
        end

        result = {
          type: 'FeatureCollection',
          features: plazas,
          count: plazas.length,
          source: 'database',
          cached_at: Time.now.iso8601
        }

        redis.setex(cache_key, CACHE_TTL, JSON.generate(result))
        result
      rescue StandardError => e
        Services::LoggerService.log_api_call(
          service: 'GIS Cache',
          endpoint: 'cached_plazas',
          error: e.message,
          success: false
        )
        generate_plazas_geojson
      end

      def cached_trash_fence
        cache_key = 'gis:trash_fence'

        cached = redis.get(cache_key)
        return JSON.parse(cached) if cached

        fence = Boundary.trash_fence

        result = if fence
                   {
                     type: 'FeatureCollection',
                     features: [{
                       type: 'Feature',
                       geometry: {
                         type: 'Polygon',
                         coordinates: fence.coordinates
                       },
                       properties: {
                         id: fence.id,
                         name: fence.name,
                         boundary_type: fence.boundary_type
                       }
                     }],
                     count: 1,
                     source: 'database',
                     cached_at: Time.now.iso8601
                   }
                 else
                   {
                     type: 'FeatureCollection',
                     features: [],
                     count: 0,
                     source: 'database',
                     error: 'Trash fence not found'
                   }
                 end

        redis.setex(cache_key, CACHE_TTL, JSON.generate(result))
        result
      rescue StandardError => e
        Services::LoggerService.log_api_call(
          service: 'GIS Cache',
          endpoint: 'cached_trash_fence',
          error: e.message,
          success: false
        )
        generate_fence_geojson
      end

      def cached_all_landmarks
        cache_key = 'gis:landmarks:all'

        cached = redis.get(cache_key)
        return JSON.parse(cached) if cached

        landmarks = Landmark.active.map do |landmark|
          {
            name: landmark.name,
            lat: landmark.latitude.to_f,
            lng: landmark.longitude.to_f,
            type: landmark.landmark_type,
            priority: landmark_priority(landmark.landmark_type),
            description: landmark.description || landmark.name
          }
        end

        redis.setex(cache_key, CACHE_TTL, JSON.generate(landmarks))
        landmarks
      rescue StandardError => e
        Services::LoggerService.log_api_call(
          service: 'GIS Cache',
          endpoint: 'cached_all_landmarks',
          error: e.message,
          success: false
        )
        # Fallback to direct query
        generate_landmarks_json
      end

      def clear_cache!
        redis.keys('gis:*').each { |key| redis.del(key) }
        true
      rescue StandardError => e
        Services::LoggerService.log_api_call(
          service: 'GIS Cache',
          endpoint: 'clear_cache',
          error: e.message,
          success: false
        )
        false
      end

      private

      def redis
        @redis ||= Redis.new(url: REDIS_URL)
      end

      def landmark_priority(type)
        case type
        when 'center', 'sacred' then 1
        when 'medical', 'ranger' then 2
        when 'service', 'toilet' then 3
        when 'art' then 4
        else 5
        end
      end

      # Fallback methods that generate data without caching
      def generate_streets_geojson
        streets = Street.active.map do |street|
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
              width: street.width,
              active: street.active
            }
          }
        end

        {
          type: 'FeatureCollection',
          features: streets,
          count: streets.length,
          source: 'database_direct'
        }
      end

      def generate_toilets_geojson
        toilets = Landmark.active.where(landmark_type: 'toilet').map do |toilet|
          {
            type: 'Feature',
            geometry: {
              type: 'Point',
              coordinates: [toilet.longitude.to_f, toilet.latitude.to_f]
            },
            properties: {
              id: toilet.id,
              name: toilet.name,
              description: toilet.description
            }
          }
        end

        {
          type: 'FeatureCollection',
          features: toilets,
          count: toilets.length,
          source: 'database_direct'
        }
      end

      def generate_blocks_geojson
        blocks = Boundary.active.where(boundary_type: 'city_block').map do |block|
          {
            type: 'Feature',
            geometry: {
              type: 'Polygon',
              coordinates: block.coordinates
            },
            properties: {
              id: block.id,
              name: block.name,
              active: block.active
            }
          }
        end

        {
          type: 'FeatureCollection',
          features: blocks,
          count: blocks.length,
          source: 'database_direct'
        }
      end

      def generate_plazas_geojson
        plazas = Landmark.active.where(landmark_type: 'plaza').map do |plaza|
          {
            type: 'Feature',
            geometry: {
              type: 'Point',
              coordinates: [plaza.longitude.to_f, plaza.latitude.to_f]
            },
            properties: {
              id: plaza.id,
              name: plaza.name,
              description: plaza.description,
              radius: plaza.radius_meters
            }
          }
        end

        {
          type: 'FeatureCollection',
          features: plazas,
          count: plazas.length,
          source: 'database_direct'
        }
      end

      def generate_fence_geojson
        fence = Boundary.trash_fence

        if fence
          {
            type: 'FeatureCollection',
            features: [{
              type: 'Feature',
              geometry: {
                type: 'Polygon',
                coordinates: fence.coordinates
              },
              properties: {
                id: fence.id,
                name: fence.name,
                boundary_type: fence.boundary_type
              }
            }],
            count: 1,
            source: 'database_direct'
          }
        else
          {
            type: 'FeatureCollection',
            features: [],
            count: 0,
            source: 'database_direct',
            error: 'Trash fence not found'
          }
        end
      end

      def generate_landmarks_json
        Landmark.active.map do |landmark|
          {
            name: landmark.name,
            lat: landmark.latitude.to_f,
            lng: landmark.longitude.to_f,
            type: landmark.landmark_type,
            priority: landmark_priority(landmark.landmark_type),
            description: landmark.description || landmark.name
          }
        end
      end
    end
  end
end
