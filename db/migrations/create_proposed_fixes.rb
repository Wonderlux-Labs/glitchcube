# frozen_string_literal: true

Sequel.migration do
  change do
    create_table(:proposed_fixes) do
      primary_key :id

      # Error information
      String :error_class, null: false
      Text :error_message, null: false
      Text :error_backtrace
      Integer :occurrence_count, default: 1

      # Context
      String :service_name
      String :method_name
      String :file_path
      Integer :line_number
      String :environment

      # Analysis results
      Float :confidence, null: false
      Boolean :critical, default: false
      Text :analysis_reason
      Text :suggested_fix

      # Fix details (JSON)
      Text :fix_details  # JSON with description, changes, files_modified
      Text :context_data # JSON with additional context

      # Review tracking
      String :status, default: 'pending', null: false
      DateTime :reviewed_at
      DateTime :applied_at
      String :commit_sha
      Text :rejection_reason

      # Timestamps
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      # Indexes
      index :status
      index :confidence
      index :created_at
      index :service_name
      index %i[error_class error_message], name: :idx_error_signature
    end
  end
end
