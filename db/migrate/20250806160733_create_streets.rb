# frozen_string_literal: true

class CreateStreets < ActiveRecord::Migration[7.1]
  def change
    create_table :streets do |t|
      t.string :name, null: false
      t.string :street_type, null: false # 'radial' or 'arc'
      t.integer :width, null: false # Width in feet
      t.jsonb :coordinates, default: [], null: false # LineString coordinates
      t.jsonb :properties, default: {}
      t.boolean :active, default: true
      t.timestamps
    end

    add_index :streets, :name
    add_index :streets, :street_type
    add_index :streets, :active
    add_index :streets, :coordinates, using: :gin
  end
end
