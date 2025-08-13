# frozen_string_literal: true

class CreateSummaries < ActiveRecord::Migration[7.1]
  def up
    if table_exists?(:summaries)
      return # Skip the change block if the table already exists
    end

    create_table :summaries, if_not_exists: true do |t|
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
    # who needs down
  end
end
