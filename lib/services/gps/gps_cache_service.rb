# frozen_string_literal: true

# Updated to use thread-safe in-memory cache with Mutex

module Services
  class GpsCacheService
    CACHE_TTL = 5 # 5 seconds for real-time cube tracking

    # Thread-safe in-memory cache for Sinatra
    @cache = {}
    @cache_timestamps = {}
    @mutex = Mutex.new

    def self.cache_fetch(key, expires_in:)
      now = Time.now

      # Thread-safe cache read
      @mutex.synchronize do
        # Check if cache entry exists and is still valid
        if @cache[key] && @cache_timestamps[key] &&
           (now - @cache_timestamps[key]) < expires_in
          return @cache[key]
        end
      end

      # Cache miss or expired - compute new value
      value = yield

      # Thread-safe cache write
      @mutex.synchronize do
        @cache[key] = value
        @cache_timestamps[key] = now
      end

      value
    end

    def self.cached_location
      cache_fetch('gps:current_location', expires_in: CACHE_TTL) do
        Services::GpsTrackingService.new.current_location
      end
    end

    def self.cached_proximity(lat, lng)
      cache_key = "gps:proximity:#{lat.round(6)}:#{lng.round(6)}"
      cache_fetch(cache_key, expires_in: CACHE_TTL) do
        Services::GpsTrackingService.new.proximity_data(lat, lng)
      end
    end

    def self.cached_landmarks_near(lat, lng, radius_miles = 0.5)
      cache_key = "gps:landmarks:#{lat.round(6)}:#{lng.round(6)}:#{radius_miles}"
      cache_fetch(cache_key, expires_in: CACHE_TTL * 5) do # Landmarks change less frequently
        radius_meters = radius_miles * 1609.34
        Landmark.within_meters(lng, lat, radius_meters).to_a
      end
    end

    def self.cached_nearest_landmarks(lat, lng, limit = 5)
      cache_key = "gps:nearest:#{lat.round(6)}:#{lng.round(6)}:#{limit}"
      cache_fetch(cache_key, expires_in: CACHE_TTL * 5) do
        Landmark.nearest(lng: lng, lat: lat, limit: limit).to_a
      end
    end

    def self.cached_containing_boundary(lat, lng)
      cache_key = "gps:boundary:#{lat.round(6)}:#{lng.round(6)}"
      cache_fetch(cache_key, expires_in: CACHE_TTL * 10) do # Boundaries don't move
        Boundary.containing_point(lng, lat).first
      end
    end

    def self.cached_nearest_streets(lat, lng, limit = 3)
      cache_key = "gps:streets:#{lat.round(6)}:#{lng.round(6)}:#{limit}"
      cache_fetch(cache_key, expires_in: CACHE_TTL * 10) do
        Street.nearest(lng: lng, lat: lat, limit: limit).to_a
      end
    end

    # Fast cached check if cube is within trash fence
    def self.cached_within_fence?(lat, lng)
      cache_key = "gps:fence:#{lat.round(6)}:#{lng.round(6)}"
      cache_fetch(cache_key, expires_in: CACHE_TTL * 60) do # Fence doesn't move
        Boundary.cube_within_fence?(lat, lng)
      end
    end

    # Get nearest intersection (radial + arc street)
    def self.cached_nearest_intersection(lat, lng)
      cache_key = "gps:intersection:#{lat.round(6)}:#{lng.round(6)}"
      cache_fetch(cache_key, expires_in: CACHE_TTL * 10) do
        Street.nearest_intersection(lat, lng)
      end
    end

    # Get comprehensive location context using PostGIS
    def self.cached_location_context(lat, lng)
      cache_key = "gps:context:#{lat.round(5)}:#{lng.round(5)}"
      cache_fetch(cache_key, expires_in: CACHE_TTL * 5) do
        {
          intersection: cached_nearest_intersection(lat, lng),
          nearest_landmarks: cached_nearest_landmarks(lat, lng, 3),
          within_fence: cached_within_fence?(lat, lng),
          current_block: cached_containing_boundary(lat, lng),
          brc_address: Utils::BrcCoordinateService.brc_address_from_coordinates(lat, lng)
        }
      end
    end

    def self.clear_cache!
      @mutex.synchronize do
        @cache.clear
        @cache_timestamps.clear
      end
    end
  end
end
