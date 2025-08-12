# frozen_string_literal: true

class AddFlowDataToConversations < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :flow_data, :jsonb, default: {}, null: false
    add_index :conversations, :flow_data, using: :gin

    # Add comment for documentation
    change_column_comment :conversations, :flow_data,
                          'Stores conversation flow data including inner_thoughts, proactive_behaviors, and other persona-specific data'
  end
end
