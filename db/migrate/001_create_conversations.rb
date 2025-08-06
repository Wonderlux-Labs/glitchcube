# frozen_string_literal: true

class CreateConversations < ActiveRecord::Migration[7.2]
  def change
    create_table :conversations do |t|
      t.string :session_id, null: false
      t.string :persona
      t.string :source
      t.integer :message_count, default: 0
      t.decimal :total_cost, precision: 10, scale: 6, default: 0.0
      t.integer :total_tokens, default: 0
      t.jsonb :metadata, default: {}
      t.datetime :started_at
      t.datetime :ended_at

      t.timestamps
    end

    add_index :conversations, :session_id
    add_index :conversations, :started_at
    add_index :conversations, :persona
  end
end
