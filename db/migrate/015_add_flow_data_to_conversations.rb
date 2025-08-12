# frozen_string_literal: true

class AddFlowDataToConversations < ActiveRecord::Migration[7.0]
  def change
    # Indexes for fast range queries (allowing overlaps)
    create_table :summaries do |t|
      t.integer :starting_message_id, null: false
      t.integer :ending_message_id, null: false
      t.datetime :summary_date, null: false
      t.integer :message_count, null: false
      t.text :text, null: false
      t.json :metadata, default: {}, null: false
      t.timestamps
    end

    add_column :conversations, :flow_data, :jsonb, default: {}, null: false
    add_index :conversations, :flow_data, using: :gin

    add_index :summaries, :starting_message_id
    add_index :summaries, :ending_message_id
    add_index :summaries, %i[starting_message_id ending_message_id], name: 'idx_summary_message_ranges'
    add_index :summaries, :summary_date  # For time-based lookups

    # Add comment for documentation
    change_column_comment :conversations, :flow_data,
                          'Stores conversation flow data including inner_thoughts, proactive_behaviors, and other persona-specific data'
  end
end
