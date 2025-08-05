# frozen_string_literal: true

require 'redis'
require 'timeout'
require 'fileutils'

module Services
  class DatabaseStartupService
    class << self
      def ensure_databases_ready!
        redis_ok = ensure_redis_running!
        sqlite_ok = ensure_sqlite_ready!
        
        if redis_ok && sqlite_ok
          puts "✅ All databases ready"
          true
        else
          puts "⚠️  Database startup issues detected"
          puts "   Redis: #{redis_ok ? 'OK' : 'FAILED'}"
          puts "   SQLite: #{sqlite_ok ? 'OK' : 'FAILED'}"
          false
        end
      end

      def ensure_redis_running!
        return true if redis_running?

        puts "⚠️  Redis not detected, attempting to start..."
        
        if start_redis
          # Give Redis a moment to fully start
          sleep 2
          
          if redis_running?
            puts "✅ Redis started successfully"
            true
          else
            puts "❌ Redis failed to start properly"
            false
          end
        else
          puts "❌ Failed to start Redis"
          false
        end
      end

      private

      def redis_running?
        redis_url = GlitchCube.config.redis_url || 'redis://localhost:6379/0'
        
        begin
          redis = Redis.new(url: redis_url)
          Timeout.timeout(2) do
            redis.ping == 'PONG'
          end
        rescue Redis::CannotConnectError, Timeout::Error, StandardError => e
          false
        ensure
          redis&.close
        end
      end

      def start_redis
        # Check which platform we're on
        if mac?
          start_redis_mac
        elsif linux?
          start_redis_linux
        else
          puts "⚠️  Unsupported platform for auto-starting Redis"
          false
        end
      end

      def mac?
        RUBY_PLATFORM.include?('darwin')
      end

      def linux?
        RUBY_PLATFORM.include?('linux')
      end

      def start_redis_mac
        # Check if Homebrew is installed
        unless system('which brew > /dev/null 2>&1')
          puts "❌ Homebrew not found. Please install Redis manually."
          return false
        end

        # Check if Redis is installed via Homebrew
        unless system('brew list redis > /dev/null 2>&1')
          puts "❌ Redis not installed. Run: brew install redis"
          return false
        end

        # Start Redis using brew services
        system('brew services start redis > /dev/null 2>&1')
      end

      def start_redis_linux
        # Try systemctl first (systemd)
        if system('which systemctl > /dev/null 2>&1')
          system('sudo systemctl start redis > /dev/null 2>&1') ||
            system('sudo systemctl start redis-server > /dev/null 2>&1')
        # Try service command (SysV init)
        elsif system('which service > /dev/null 2>&1')
          system('sudo service redis start > /dev/null 2>&1') ||
            system('sudo service redis-server start > /dev/null 2>&1')
        else
          puts "❌ Cannot determine how to start Redis on this Linux system"
          false
        end
      end

      def ensure_sqlite_ready!
        database_url = GlitchCube.config.database_url || 'sqlite://data/glitchcube.db'
        
        # Skip SQLite check if using a different database
        unless database_url.start_with?('sqlite://')
          puts "✅ Using non-SQLite database: #{database_url.split('@').last}"
          return true
        end

        # Extract SQLite file path
        sqlite_path = database_url.gsub('sqlite://', '')
        
        # Skip for in-memory databases
        if sqlite_path == ':memory:'
          puts "✅ Using in-memory SQLite database"
          return true
        end

        # Ensure directory exists
        dir = File.dirname(sqlite_path)
        unless File.directory?(dir)
          puts "📁 Creating directory for SQLite: #{dir}"
          FileUtils.mkdir_p(dir)
        end

        # Check if SQLite3 command is available
        if system('which sqlite3 > /dev/null 2>&1')
          puts "✅ SQLite3 command available"
          
          # Touch the file if it doesn't exist
          unless File.exist?(sqlite_path)
            puts "📝 Creating SQLite database: #{sqlite_path}"
            FileUtils.touch(sqlite_path)
          end
          
          # Test database connectivity
          if test_sqlite_connection(sqlite_path)
            puts "✅ SQLite database accessible: #{sqlite_path}"
            true
          else
            puts "❌ SQLite database not accessible: #{sqlite_path}"
            false
          end
        else
          puts "⚠️  SQLite3 command not found, but Ruby sqlite3 gem may still work"
          # Still return true as the Ruby gem might work without the CLI
          true
        end
      end

      def test_sqlite_connection(path)
        # Test with sqlite3 command
        system("sqlite3 #{path} '.tables' > /dev/null 2>&1")
      rescue StandardError => e
        puts "❌ SQLite test failed: #{e.message}"
        false
      end
    end
  end
end