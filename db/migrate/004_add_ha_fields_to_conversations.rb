# frozen_string_literal: true

class AddHaFieldsToConversations < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :ha_conversation_id, :string
    add_column :conversations, :ha_device_id, :string
    add_column :conversations, :continue_conversation, :boolean, default: true
    
    # Add indexes for faster lookups
    add_index :conversations, :ha_conversation_id
    add_index :conversations, :ha_device_id
    
    # Add index for finding active conversations
    add_index :conversations, [:ha_conversation_id, :ended_at]
  end
end