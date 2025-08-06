# frozen_string_literal: true
# Updated to use simple in-memory cache instead of Rails.cache

module Services
  class GpsCacheService
    CACHE_TTL = 5 # 5 seconds for real-time cube tracking
    
    # Simple in-memory cache for Sinatra
    @cache = {}
    @cache_timestamps = {}
    
    def self.cache_fetch(key, expires_in:)
      now = Time.now
      
      # Check if cache entry exists and is still valid
      if @cache[key] && @cache_timestamps[key] && 
         (now - @cache_timestamps[key]) < expires_in
        return @cache[key]
      end
      
      # Cache miss or expired - compute new value
      value = yield
      @cache[key] = value
      @cache_timestamps[key] = now
      value
    end
    
    def self.cached_location
      cache_fetch("gps:current_location", expires_in: CACHE_TTL) do
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
        Landmark.near_location(lat, lng, radius_miles)
      end
    end
    
    def self.clear_cache!
      @cache.clear
      @cache_timestamps.clear
    end
  end
end