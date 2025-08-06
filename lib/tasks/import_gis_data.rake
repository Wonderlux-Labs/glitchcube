# frozen_string_literal: true

namespace :gis do
  desc 'Import GIS data from data/gis directory into ActiveRecord models'
  task :import do
    puts '🗺️  Starting GIS data import...'
    
    # Get the root directory
    root_dir = Rails.root rescue File.expand_path('../../..', __dir__)
    gis_data_path = File.join(root_dir, 'data', 'gis')
    
    unless Dir.exist?(gis_data_path)
      puts "❌ GIS data directory not found: #{gis_data_path}"
      exit 1
    end
    
    puts "📁 Importing from: #{gis_data_path}"
    
    begin
      # Clear existing landmarks (optional - comment out to preserve existing data)
      puts '🧹 Clearing existing landmarks...'
      Landmark.delete_all
      
      # Import all GIS data
      Landmark.import_from_gis_data(gis_data_path)
      
      # Display results
      puts "\n✅ Import completed successfully!"
      puts "📊 Summary:"
      
      Landmark.group(:landmark_type).count.each do |type, count|
        icon = case type
               when 'center' then '🔥'
               when 'sacred' then '🏛️'
               when 'toilet' then '🚻'
               when 'plaza' then '🏛️'
               else '📍'
               end
        puts "   #{icon} #{type.capitalize}: #{count}"
      end
      
      puts "   📍 Total landmarks: #{Landmark.count}"
      
    rescue => e
      puts "❌ Import failed: #{e.message}"
      puts e.backtrace.first(5)
      exit 1
    end
  end
  
  desc 'Export landmarks to seeds.rb format'
  task :export_seeds => :environment do
    puts '📦 Generating seeds.rb from landmark data...'
    
    seeds_content = "# frozen_string_literal: true\n\n"
    seeds_content += "# Auto-generated from GIS data on #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}\n\n"
    seeds_content += "puts '🗺️  Creating landmarks from GIS data...'\n\n"
    
    Landmark.order(:landmark_type, :name).each do |landmark|
      seeds_content += "Landmark.find_or_create_by!(\n"
      seeds_content += "  name: #{landmark.name.inspect},\n"
      seeds_content += "  landmark_type: #{landmark.landmark_type.inspect}\n"
      seeds_content += ") do |l|\n"
      seeds_content += "  l.latitude = #{landmark.latitude}\n"
      seeds_content += "  l.longitude = #{landmark.longitude}\n"
      seeds_content += "  l.icon = #{landmark.icon.inspect}\n" if landmark.icon
      seeds_content += "  l.radius_meters = #{landmark.radius_meters}\n"
      seeds_content += "  l.description = #{landmark.description.inspect}\n" if landmark.description
      seeds_content += "  l.properties = #{landmark.properties.inspect}\n" unless landmark.properties.empty?
      seeds_content += "  l.active = #{landmark.active}\n"
      seeds_content += "end\n\n"
    end
    
    seeds_content += "puts \"✅ Created #{Landmark.count} landmarks\"\n"
    
    # Write to seeds file
    root_dir = Rails.root rescue File.expand_path('../../..', __dir__)
    seeds_file = File.join(root_dir, 'db', 'seeds.rb')
    
    File.write(seeds_file, seeds_content)
    puts "✅ Seeds exported to: #{seeds_file}"
    puts "💡 Run with: bundle exec rake db:seed"
  end
  
  desc 'Show landmark statistics'
  task :stats => :environment do
    puts '📊 Landmark Statistics:'
    puts "   Total landmarks: #{Landmark.count}"
    puts "   Active landmarks: #{Landmark.active.count}"
    puts
    puts '📋 By type:'
    Landmark.group(:landmark_type).count.sort.each do |type, count|
      icon = case type
             when 'center' then '🔥'
             when 'sacred' then '🏛️'
             when 'toilet' then '🚻'
             when 'plaza' then '🏛️'
             else '📍'
             end
      puts "   #{icon} #{type.capitalize}: #{count}"
    end
  end
end