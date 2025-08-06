class CreateApiCalls < ActiveRecord::Migration[7.2]
  def change
    create_table :api_calls do |t|
      t.string :service, null: false # 'openrouter', 'home_assistant'
      t.string :endpoint
      t.string :method
      t.integer :status_code
      t.integer :duration_ms
      t.string :model_used
      t.integer :tokens_used
      t.jsonb :request_data, default: {}
      t.jsonb :response_data, default: {}
      t.string :error_message
      
      t.timestamps
    end
    
    add_index :api_calls, :service
    add_index :api_calls, :created_at
    add_index :api_calls, [:service, :endpoint]
  end
end