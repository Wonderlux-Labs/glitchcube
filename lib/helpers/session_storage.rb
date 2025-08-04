# frozen_string_literal: true

require 'redis'
require 'json'
require 'thread'

module Helpers
  # Flexible session storage helper that can use Redis or fall back to thread-safe memory storage
  # Provides consistent interface regardless of backend
  class SessionStorage
    class << self
      # Initialize storage backend based on availability
      def configure!
        @storage_backend = determine_backend
        @memory_storage = {} if @storage_backend == :memory
        @memory_mutex = Mutex.new if @storage_backend == :memory
        
        puts "📦 SessionStorage configured with #{@storage_backend} backend"
      end

      # Store session data with automatic serialization
      def set(session_id, key, value, ttl: 3600)
        case @storage_backend
        when :redis
          redis_set(session_id, key, value, ttl)
        when :memory
          memory_set(session_id, key, value, ttl)
        else
          raise 'SessionStorage not configured. Call SessionStorage.configure! first'
        end
      end

      # Retrieve session data with automatic deserialization
      def get(session_id, key)
        case @storage_backend
        when :redis
          redis_get(session_id, key)
        when :memory
          memory_get(session_id, key)
        else
          raise 'SessionStorage not configured. Call SessionStorage.configure! first'
        end
      end

      # Get all session data for a session ID
      def get_session(session_id)
        case @storage_backend
        when :redis
          redis_get_session(session_id)
        when :memory
          memory_get_session(session_id)
        else
          {}
        end
      end

      # Delete specific key from session
      def delete(session_id, key)
        case @storage_backend
        when :redis
          redis_delete(session_id, key)
        when :memory
          memory_delete(session_id, key)
        end
      end

      # Clear entire session
      def clear_session(session_id)
        case @storage_backend
        when :redis
          redis_clear_session(session_id)
        when :memory
          memory_clear_session(session_id)
        end
      end

      # Check if session exists
      def exists?(session_id)
        case @storage_backend
        when :redis
          redis_exists?(session_id)
        when :memory
          memory_exists?(session_id)
        else
          false
        end
      end

      # Cleanup expired sessions (mainly for memory backend)
      def cleanup_expired!
        return unless @storage_backend == :memory
        
        @memory_mutex.synchronize do
          current_time = Time.now.to_i
          @memory_storage.delete_if do |session_id, session_data|
            expired = session_data[:expires_at] && session_data[:expires_at] < current_time
            puts "🗑️  Cleaned up expired session: #{session_id}" if expired
            expired
          end
        end
      end

      # Get storage statistics
      def stats
        case @storage_backend
        when :redis
          redis_stats
        when :memory
          memory_stats
        else
          { backend: 'unconfigured', sessions: 0 }
        end
      end

      private

      def determine_backend
        # Try Redis first if available
        if redis_available?
          :redis
        else
          puts "⚠️  Redis not available, falling back to thread-safe memory storage"
          :memory
        end
      end

      def redis_available?
        return false unless GlitchCube.config.redis_url

        Redis.new(url: GlitchCube.config.redis_url).ping == 'PONG'
      rescue StandardError => e
        puts "Redis connection failed: #{e.message}"
        false
      end

      def redis_client
        @redis_client ||= Redis.new(url: GlitchCube.config.redis_url)
      end

      # Redis backend methods
      def redis_set(session_id, key, value, ttl)
        session_key = "session:#{session_id}"
        field_key = key.to_s
        
        redis_client.hset(session_key, field_key, serialize_value(value))
        redis_client.expire(session_key, ttl)
      end

      def redis_get(session_id, key)
        session_key = "session:#{session_id}"
        field_key = key.to_s
        
        value = redis_client.hget(session_key, field_key)
        deserialize_value(value)
      end

      def redis_get_session(session_id)
        session_key = "session:#{session_id}"
        session_data = redis_client.hgetall(session_key)
        
        session_data.transform_values { |v| deserialize_value(v) }
      end

      def redis_delete(session_id, key)
        session_key = "session:#{session_id}"
        field_key = key.to_s
        
        redis_client.hdel(session_key, field_key)
      end

      def redis_clear_session(session_id)
        session_key = "session:#{session_id}"
        redis_client.del(session_key)
      end

      def redis_exists?(session_id)
        session_key = "session:#{session_id}"
        redis_client.exists?(session_key) > 0
      end

      def redis_stats
        info = redis_client.info
        {
          backend: 'redis',
          sessions: redis_client.keys('session:*').length,
          memory_usage: info['used_memory_human'],
          connected_clients: info['connected_clients']
        }
      end

      # Memory backend methods (thread-safe)
      def memory_set(session_id, key, value, ttl)
        @memory_mutex.synchronize do
          @memory_storage[session_id] ||= { data: {}, expires_at: nil }
          @memory_storage[session_id][:data][key.to_s] = value
          @memory_storage[session_id][:expires_at] = Time.now.to_i + ttl
        end
      end

      def memory_get(session_id, key)
        @memory_mutex.synchronize do
          session_data = @memory_storage[session_id]
          return nil unless session_data
          return nil if session_expired?(session_data)
          
          session_data[:data][key.to_s]
        end
      end

      def memory_get_session(session_id)
        @memory_mutex.synchronize do
          session_data = @memory_storage[session_id]
          return {} unless session_data
          return {} if session_expired?(session_data)
          
          session_data[:data] || {}
        end
      end

      def memory_delete(session_id, key)
        @memory_mutex.synchronize do
          session_data = @memory_storage[session_id]
          return unless session_data
          
          session_data[:data].delete(key.to_s)
        end
      end

      def memory_clear_session(session_id)
        @memory_mutex.synchronize do
          @memory_storage.delete(session_id)
        end
      end

      def memory_exists?(session_id)
        @memory_mutex.synchronize do
          session_data = @memory_storage[session_id]
          return false unless session_data
          
          !session_expired?(session_data)
        end
      end

      def memory_stats
        @memory_mutex.synchronize do
          active_sessions = @memory_storage.count do |_session_id, session_data|
            !session_expired?(session_data)
          end
          
          {
            backend: 'memory',
            sessions: active_sessions,
            total_sessions: @memory_storage.length,
            memory_usage: "#{@memory_storage.to_s.bytesize / 1024}KB (estimated)"
          }
        end
      end

      def session_expired?(session_data)
        session_data[:expires_at] && session_data[:expires_at] < Time.now.to_i
      end

      # Serialization helpers
      def serialize_value(value)
        JSON.generate(value)
      rescue JSON::GeneratorError
        value.to_s
      end

      def deserialize_value(value)
        return nil if value.nil?
        
        JSON.parse(value)
      rescue JSON::ParserError
        value
      end
    end
  end
end