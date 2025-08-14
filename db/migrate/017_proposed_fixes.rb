# frozen_string_literal: true

class ProposedFixes < ActiveRecord::Migration[7.0]
  def change
    create_table :proposed_fixes do |t|
      # Core error identification
      t.string :error_class, null: false
      t.text :error_message, null: false
      t.string :service_name

      # Fix details and confidence
      t.text :fix_details # JSON serialized
      t.text :context_data # JSON serialized
      t.decimal :confidence, precision: 3, scale: 2, default: 0.0

      # Review and status tracking
      t.string :status, default: 'pending', null: false
      t.datetime :reviewed_at
      t.text :rejection_reason

      # Application tracking
      t.datetime :applied_at
      t.string :commit_sha

      # Metadata
      t.timestamps null: false
    end

    # Indexes for common queries
    add_index :proposed_fixes, :status
    add_index :proposed_fixes, :service_name
    add_index :proposed_fixes, :confidence
    add_index :proposed_fixes, :created_at
    add_index :proposed_fixes, %i[error_class error_message], name: 'index_proposed_fixes_on_error'
    add_index :proposed_fixes, %i[status confidence], name: 'index_proposed_fixes_on_status_confidence'
  end
end
