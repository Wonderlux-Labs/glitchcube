# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2025_08_06_160924) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"
  enable_extension "postgis"

  create_table "api_calls", force: :cascade do |t|
    t.string "service", null: false
    t.string "endpoint"
    t.string "method"
    t.integer "status_code"
    t.integer "duration_ms"
    t.string "model_used"
    t.integer "tokens_used"
    t.jsonb "request_data", default: {}
    t.jsonb "response_data", default: {}
    t.string "error_message"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_api_calls_on_created_at"
    t.index ["service", "endpoint"], name: "index_api_calls_on_service_and_endpoint"
    t.index ["service"], name: "index_api_calls_on_service"
  end

  create_table "boundaries", force: :cascade do |t|
    t.string "name", null: false
    t.string "boundary_type", null: false
    t.jsonb "coordinates", default: [], null: false
    t.text "description"
    t.jsonb "properties", default: {}
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_boundaries_on_active"
    t.index ["boundary_type"], name: "index_boundaries_on_boundary_type"
    t.index ["coordinates"], name: "index_boundaries_on_coordinates", using: :gin
    t.index ["name"], name: "index_boundaries_on_name"
  end

  create_table "conversations", force: :cascade do |t|
    t.string "session_id", null: false
    t.string "persona"
    t.string "source"
    t.integer "message_count", default: 0
    t.decimal "total_cost", precision: 10, scale: 6, default: "0.0"
    t.integer "total_tokens", default: 0
    t.jsonb "metadata", default: {}
    t.datetime "started_at"
    t.datetime "ended_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "ha_conversation_id"
    t.string "ha_device_id"
    t.boolean "continue_conversation", default: true
    t.index ["ha_conversation_id", "ended_at"], name: "index_conversations_on_ha_conversation_id_and_ended_at"
    t.index ["ha_conversation_id"], name: "index_conversations_on_ha_conversation_id"
    t.index ["ha_device_id"], name: "index_conversations_on_ha_device_id"
    t.index ["persona"], name: "index_conversations_on_persona"
    t.index ["session_id"], name: "index_conversations_on_session_id"
    t.index ["started_at"], name: "index_conversations_on_started_at"
  end

  create_table "landmarks", force: :cascade do |t|
    t.string "name", null: false
    t.decimal "latitude", precision: 10, scale: 8, null: false
    t.decimal "longitude", precision: 11, scale: 8, null: false
    t.string "landmark_type"
    t.integer "radius_meters", default: 30
    t.string "icon"
    t.text "description"
    t.jsonb "properties", default: {}
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.geography "location", limit: {srid: 4326, type: "st_point"}
    t.index ["active"], name: "index_landmarks_on_active"
    t.index ["landmark_type"], name: "index_landmarks_on_landmark_type"
    t.index ["latitude", "longitude"], name: "index_landmarks_on_latitude_and_longitude"
    t.index ["location"], name: "index_landmarks_on_location", using: :gist
    t.index ["name"], name: "index_landmarks_on_name"
    t.check_constraint "location IS NOT NULL OR latitude IS NULL AND longitude IS NULL", name: "landmarks_location_consistency"
  end

  create_table "memories", force: :cascade do |t|
    t.text "content", null: false
    t.jsonb "data", default: {}, null: false
    t.integer "recall_count", default: 0
    t.datetime "last_recalled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_memories_on_created_at"
    t.index ["data"], name: "index_memories_on_data", using: :gin
    t.index ["recall_count", "created_at"], name: "index_memories_on_recall_count_and_created_at"
    t.index ["recall_count"], name: "index_memories_on_recall_count"
  end

  create_table "messages", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.string "role", null: false
    t.text "content", null: false
    t.string "persona"
    t.string "model_used"
    t.integer "prompt_tokens"
    t.integer "completion_tokens"
    t.decimal "cost", precision: 10, scale: 6
    t.integer "response_time_ms"
    t.jsonb "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id"], name: "index_messages_on_conversation_id"
    t.index ["created_at"], name: "index_messages_on_created_at"
    t.index ["model_used"], name: "index_messages_on_model_used"
    t.index ["role"], name: "index_messages_on_role"
  end

  create_table "streets", force: :cascade do |t|
    t.string "name", null: false
    t.string "street_type", null: false
    t.integer "width", null: false
    t.jsonb "coordinates", default: [], null: false
    t.jsonb "properties", default: {}
    t.boolean "active", default: true
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_streets_on_active"
    t.index ["coordinates"], name: "index_streets_on_coordinates", using: :gin
    t.index ["name"], name: "index_streets_on_name"
    t.index ["street_type"], name: "index_streets_on_street_type"
  end

  add_foreign_key "messages", "conversations"
end
