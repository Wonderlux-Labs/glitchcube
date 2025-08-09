# frozen_string_literal: true

namespace :db do
  desc 'Seed location data if not present (idempotent)'
  task seed_locations: :load_config do
    puts '🗺️  Checking location data...'

    # Check if we have any landmarks
    landmark_count = Landmark.count

    if landmark_count.positive?
      puts "✅ Location data already present (#{landmark_count} landmarks)"

      # Verify critical landmarks
      critical_landmarks = ['The Man', 'The Temple', 'Center Camp']
      missing = critical_landmarks.reject { |name| Landmark.exists?(name: name) }

      if missing.any?
        puts "⚠️  Missing critical landmarks: #{missing.join(', ')}"
        puts '   Running full seed to restore...'
        Rake::Task['db:seed'].invoke
      else
        puts '✅ All critical landmarks present'
      end
    else
      puts '📍 No location data found, seeding...'

      # Check if GIS data exists
      gis_data_path = File.expand_path('../../data/gis', __dir__)

      unless Dir.exist?(gis_data_path)
        puts '📥 Downloading GIS data first...'
        download_script = File.expand_path('../../scripts/download_bm2025_data.rb', __dir__)

        if File.exist?(download_script)
          system("bundle exec ruby #{download_script}")
        else
          puts "❌ Download script not found: #{download_script}"
          puts '   Please run: bundle exec ruby scripts/download_bm2025_data.rb'
          exit 1
        end
      end

      # Run the seeds
      Rake::Task['db:seed'].invoke
    end

    # Show summary
    puts "\n📊 Location data summary:"
    Landmark.group(:landmark_type).count.sort.each do |type, count|
      icon = case type
             when 'center' then '🔥'
             when 'sacred' then '🏛️'
             when 'toilet' then '🚻'
             when 'plaza' then '🎪' # Different icon to avoid duplicate branch
             when 'cpn' then '🏕️' # Different icon to avoid duplicate with else
             when 'medical' then '🏥'
             when 'ranger' then '👮'
             else '📍'
             end
      puts "   #{icon} #{type.capitalize}: #{count}"
    end
    puts "   📍 Total: #{Landmark.count}"
  end

  # Hook into migrations to auto-seed locations
  if Rake::Task.task_defined?('db:migrate')
    Rake::Task['db:migrate'].enhance do
      Rake::Task['db:seed_locations'].invoke
    end
  end

  # Also hook into schema/structure loads
  ['db:schema:load', 'db:structure:load', 'db:reset'].each do |task_name|
    next unless Rake::Task.task_defined?(task_name)

    Rake::Task[task_name].enhance do
      Rake::Task['db:seed_locations'].invoke
    end
  end

  desc 'Download GIS data and seed locations'
  task setup_locations: :load_config do
    puts '🔥 Setting up Burning Man location data...'

    # Download GIS data if needed
    gis_data_path = File.expand_path('../../data/gis', __dir__)

    if Dir.exist?(gis_data_path) && !Dir.empty?(gis_data_path)
      puts '✅ GIS data already present'
    else
      puts '📥 Downloading GIS data...'
      download_script = File.expand_path('../../scripts/download_bm2025_data.rb', __dir__)
      system("bundle exec ruby #{download_script}")
    end

    # Seed the data
    Rake::Task['db:seed'].invoke

    puts "\n🎉 Location setup complete!"
  end
end

# Convenience aliases
desc 'Ensure location data is present (alias for db:seed_locations)'
task seed_locations: 'db:seed_locations'

desc 'Setup all location data (download + seed)'
task setup_locations: 'db:setup_locations'
