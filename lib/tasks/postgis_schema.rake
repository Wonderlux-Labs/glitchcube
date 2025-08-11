# frozen_string_literal: true

namespace :db do
  desc 'Dump schema using pg_dump (works with PostGIS)'
  task structure_dump: :load_config do
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    db_name = config[:database]
    host = config[:host] || 'localhost'
    port = config[:port] || 5432
    username = config[:username] || 'postgres'

    puts "Dumping structure for #{db_name}..."

    # Use pg_dump to create a SQL dump with PostGIS support
    cmd = "pg_dump -h #{host} -p #{port} -U #{username} -d #{db_name} --schema-only --no-owner --no-privileges -f db/structure.sql"

    # Set PGPASSWORD environment variable if password is provided
    if config[:password]
      cmd = "PGPASSWORD='#{config[:password]}' #{cmd}"
    end

    system(cmd)

    if $?.success?
      puts '✅ Structure dumped to db/structure.sql'
    else
      puts '❌ Failed to dump structure'
    end
  end

  desc 'Load structure from SQL dump (works with PostGIS)'
  task structure_load: :load_config do
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    db_name = config[:database]
    host = config[:host] || 'localhost'
    port = config[:port] || 5432
    username = config[:username] || 'postgres'

    unless File.exist?('db/structure.sql')
      puts '❌ db/structure.sql not found'
      exit 1
    end

    puts "Loading structure for #{db_name}..."

    # Use psql to load the SQL dump
    cmd = "psql -h #{host} -p #{port} -U #{username} -d #{db_name} -f db/structure.sql"

    # Set PGPASSWORD environment variable if password is provided
    if config[:password]
      cmd = "PGPASSWORD='#{config[:password]}' #{cmd}"
    end

    system(cmd)

    if $?.success?
      puts '✅ Structure loaded from db/structure.sql'
    else
      puts '❌ Failed to load structure'
    end
  end
end
