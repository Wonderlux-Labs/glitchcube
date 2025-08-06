# frozen_string_literal: true

class CreateMemories < ActiveRecord::Migration[7.1]
  def change
    create_table :memories do |t|
      # Essential fields only
      t.text :content, null: false # The story/memory as we'd tell it
      t.jsonb :data, default: {}, null: false # EVERYTHING else goes here - flexible for experimentation

      # Usage tracking
      t.integer :recall_count, default: 0
      t.datetime :last_recalled_at

      t.timestamps
    end

    # GIN index for efficient JSONB queries
    add_index :memories, :data, using: :gin

    # Basic indexes for common queries
    add_index :memories, :created_at
    add_index :memories, :recall_count

    # Composite index for freshness queries
    add_index :memories, %i[recall_count created_at]
  end
end
