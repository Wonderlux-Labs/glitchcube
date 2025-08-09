# frozen_string_literal: true

class AddUniqueIndexToSessionId < ActiveRecord::Migration[7.1]
  def change
    # Remove the non-unique index
    remove_index :conversations, :session_id if index_exists?(:conversations, :session_id)

    # Add a unique index to ensure session_id is unique
    add_index :conversations, :session_id, unique: true
  end
end
