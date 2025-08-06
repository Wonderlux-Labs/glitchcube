# frozen_string_literal: true

namespace :postgis do
  desc 'Setup PostGIS extension and spatial data for landmarks'
  task :setup do
    require './app'
    puts '🗄️  Setting up PostGIS for spatial queries...'
    
    begin
      # Run the PostGIS migration
      puts '⚡ Running PostGIS migration...'
      system('bundle exec rake db:migrate VERSION=20250806')
      
      # Verify PostGIS is working
      puts '🔍 Verifying PostGIS installation...'
      result = ActiveRecord::Base.connection.execute("SELECT PostGIS_version()")
      if result.present?
        version = result.first['postgis_version']
        puts "✅ PostGIS #{version} is installed and working!"
      else
        puts "❌ PostGIS not available"
        return
      end
      
      # Update existing landmarks with spatial data
      puts '📍 Updating existing landmarks with spatial location data...'
      updated = 0
      Landmark.find_each do |landmark|
        if landmark.latitude.present? && landmark.longitude.present?
          landmark.save! # Trigger the spatial location update callback
          updated += 1
        end
      end
      puts "✅ Updated #{updated} landmarks with spatial data"
      
      # Test spatial queries
      puts '🧪 Testing spatial queries...'
      center_camp = { lat: 40.786958, lng: -119.202994 }
      
      # Test with BM-appropriate distances (25 feet = ~0.005 miles)
      nearby = Landmark.near_location(center_camp[:lat], center_camp[:lng], 25.0/5280.0)
      puts "✅ Found #{nearby.count} landmarks near Center Camp (25 feet radius)"
      
      # Show performance comparison if landmarks exist
      if Landmark.count > 0
        puts '⚡ Performance test results:'
        
        # Test PostGIS performance
        start_time = Time.now
        spatial_results = Landmark.near_location(center_camp[:lat], center_camp[:lng], 1.0).limit(10)
        spatial_time = Time.now - start_time
        puts "   PostGIS spatial query: #{(spatial_time * 1000).round(2)}ms (#{spatial_results.count} results)"
        
        puts '🎉 PostGIS setup complete!'
      else
        puts '⚠️  No landmarks found. Run `bundle exec rake db:seed` first.'
      end
      
    rescue StandardError => e
      puts "❌ PostGIS setup failed: #{e.message}"
      puts "   This is normal if you're not using PostgreSQL or PostGIS isn't installed."
      puts "   The system will fallback to regular coordinate calculations."
    end
  end
  
  desc 'Test PostGIS spatial queries performance'
  task :test do
    require './app'
    if Landmark.count == 0
      puts '⚠️  No landmarks found. Run `bundle exec rake db:seed` first.'
      return
    end
    
    puts '🧪 Testing spatial query performance...'
    center_camp = { lat: 40.786958, lng: -119.202994 }
    
    # Test different radius sizes
    [0.1, 0.5, 1.0, 2.0].each do |radius|
      start_time = Time.now
      results = Landmark.near_location(center_camp[:lat], center_camp[:lng], radius)
      query_time = Time.now - start_time
      
      puts "   #{radius} mile radius: #{(query_time * 1000).round(2)}ms (#{results.count} landmarks)"
    end
    
    puts '✅ Performance test complete!'
  end
end