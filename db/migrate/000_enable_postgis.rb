# frozen_string_literal: true

class EnablePostgis < ActiveRecord::Migration[7.1]
  def up
    # Enable PostGIS extension - must be the very first migration
    enable_extension 'postgis'
  end

  def down
    # Don't disable PostGIS as other migrations may depend on it
    # disable_extension 'postgis'
  end
end
