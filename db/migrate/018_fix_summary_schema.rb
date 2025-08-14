# frozen_string_literal: true

class FixSummarySchema < ActiveRecord::Migration[7.1]
  def up
    # Check if we need to modify the summaries table
    return unless table_exists?(:summaries)

    # Check if table has the old schema (from migration 015)
    has_old_schema = column_exists?(:summaries, :summary_date)
    return unless has_old_schema

    # Drop the old table and recreate with correct schema
    drop_table :summaries

    create_table :summaries do |t|
      t.string :summary_type, null: false # personal, interaction, event, daily
      t.string :period, null: false # hourly, daily
      t.text :content, null: false
      t.jsonb :metadata, default: {}
      t.timestamps
    end

    add_index :summaries, :summary_type
    add_index :summaries, :period
    add_index :summaries, :created_at
    add_index :summaries, %i[summary_type period created_at]
  end

  def down
    # Revert to old schema
    drop_table :summaries if table_exists?(:summaries)

    create_table :summaries do |t|
      t.integer :starting_message_id
      t.integer :ending_message_id
      t.date :summary_date, null: false
      t.integer :message_count, default: 0
      t.text :text
      t.jsonb :metadata, default: {}
      t.timestamps
    end
  end
end
