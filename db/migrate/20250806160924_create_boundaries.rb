# frozen_string_literal: true

class CreateBoundaries < ActiveRecord::Migration[7.1]
  def change
    create_table :boundaries do |t|
      t.string :name, null: false
      t.string :boundary_type, null: false # 'fence', 'zone', etc.
      t.jsonb :coordinates, default: [], null: false # Polygon coordinates
      t.text :description
      t.jsonb :properties, default: {}
      t.boolean :active, default: true
      t.timestamps
    end

    add_index :boundaries, :name
    add_index :boundaries, :boundary_type
    add_index :boundaries, :active
    add_index :boundaries, :coordinates, using: :gin
    
    # Import all GIS data now that all tables are created
    puts "🌱 Running database seeder after migration..."
    
    # Import landmarks, streets, and boundaries
    Landmark.import_from_gis_data('data/gis')
    
    # Create trash fence boundary  
    Boundary.create_trash_fence!
    
    # Report what was imported
    landmark_count = Landmark.count
    street_count = Street.count
    boundary_count = Boundary.count
    
    puts "✅ Imported #{landmark_count} landmarks, #{street_count} streets, #{boundary_count} boundaries"
  end
end
