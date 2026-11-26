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

ActiveRecord::Schema[8.1].define(version: 2026_11_26_072000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "candidate_votes", force: :cascade do |t|
    t.bigint "participant_id", null: false
    t.bigint "candidate_id", null: false
    t.boolean "approved", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["candidate_id"], name: "index_candidate_votes_on_candidate_id"
    t.index ["participant_id", "candidate_id"], name: "index_candidate_votes_on_participant_id_and_candidate_id", unique: true
    t.index ["participant_id"], name: "index_candidate_votes_on_participant_id"
  end

  create_table "candidates", force: :cascade do |t|
    t.bigint "nomikai_id", null: false
    t.bigint "venue_id", null: false
    t.decimal "score", precision: 5, scale: 2
    t.integer "rank"
    t.text "reason"
    t.boolean "selected", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["nomikai_id", "venue_id"], name: "index_candidates_on_nomikai_id_and_venue_id", unique: true
    t.index ["nomikai_id"], name: "index_candidates_on_nomikai_id"
    t.index ["venue_id"], name: "index_candidates_on_venue_id"
  end

  create_table "invitations", force: :cascade do |t|
    t.bigint "nomikai_id", null: false
    t.string "email", null: false
    t.string "token", null: false
    t.string "status", default: "pending", null: false
    t.datetime "sent_at"
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["nomikai_id", "email"], name: "index_invitations_on_nomikai_id_and_email", unique: true
    t.index ["nomikai_id"], name: "index_invitations_on_nomikai_id"
    t.index ["token"], name: "index_invitations_on_token", unique: true
  end

  create_table "nomikai_vibe_cards", force: :cascade do |t|
    t.bigint "nomikai_id", null: false
    t.bigint "vibe_card_id", null: false
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["nomikai_id", "vibe_card_id"], name: "index_nomikai_vibe_cards_on_nomikai_id_and_vibe_card_id", unique: true
    t.index ["nomikai_id"], name: "index_nomikai_vibe_cards_on_nomikai_id"
    t.index ["vibe_card_id"], name: "index_nomikai_vibe_cards_on_vibe_card_id"
  end

  create_table "nomikais", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "name"
    t.string "area"
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.datetime "event_date"
    t.integer "group_size"
    t.integer "budget_per_person"
    t.string "status", default: "open", null: false
    t.string "share_token"
    t.text "preference_summary"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "join_code", null: false
    t.string "meal_period", default: "dinner", null: false
    t.datetime "matches_found_at"
    t.index ["join_code"], name: "index_nomikais_on_join_code", unique: true
    t.index ["share_token"], name: "index_nomikais_on_share_token", unique: true
    t.index ["user_id"], name: "index_nomikais_on_user_id"
    t.index ["user_id"], name: "index_nomikais_one_ongoing_per_user", unique: true, where: "(((status)::text = 'open'::text) AND (matches_found_at IS NULL))"
  end

  create_table "participants", force: :cascade do |t|
    t.bigint "nomikai_id", null: false
    t.string "nickname"
    t.string "token"
    t.integer "budget_max"
    t.string "restrictions", default: [], null: false, array: true
    t.boolean "non_drinker", default: false, null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "invitation_id"
    t.bigint "user_id"
    t.index ["invitation_id"], name: "index_participants_on_invitation_id", unique: true
    t.index ["nomikai_id", "user_id"], name: "index_participants_one_per_account", unique: true, where: "(user_id IS NOT NULL)"
    t.index ["nomikai_id"], name: "index_participants_on_nomikai_id"
    t.index ["token"], name: "index_participants_on_token", unique: true
    t.index ["user_id"], name: "index_participants_on_user_id"
  end

  create_table "swipes", force: :cascade do |t|
    t.bigint "participant_id", null: false
    t.bigint "nomikai_vibe_card_id", null: false
    t.boolean "liked", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["nomikai_vibe_card_id"], name: "index_swipes_on_nomikai_vibe_card_id"
    t.index ["participant_id", "nomikai_vibe_card_id"], name: "index_swipes_on_participant_id_and_nomikai_vibe_card_id", unique: true
    t.index ["participant_id"], name: "index_swipes_on_participant_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "venues", force: :cascade do |t|
    t.string "google_place_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "name"
    t.text "formatted_address"
    t.string "price_level"
    t.text "google_maps_uri"
    t.decimal "rating", precision: 2, scale: 1
    t.index ["google_place_id"], name: "index_venues_on_google_place_id", unique: true
  end

  create_table "vibe_cards", force: :cascade do |t|
    t.string "title"
    t.string "image_url"
    t.jsonb "vibe_scores", default: {}, null: false
    t.text "description"
    t.integer "min_budget"
    t.integer "max_budget"
    t.integer "min_group_size"
    t.integer "max_group_size"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "image_type"
    t.string "source_key"
    t.string "source_url"
    t.string "license_url"
    t.string "photographer"
    t.string "cuisine"
    t.index ["source_key"], name: "index_vibe_cards_on_source_key", unique: true
  end

  add_foreign_key "candidate_votes", "candidates"
  add_foreign_key "candidate_votes", "participants"
  add_foreign_key "candidates", "nomikais"
  add_foreign_key "candidates", "venues"
  add_foreign_key "invitations", "nomikais"
  add_foreign_key "nomikai_vibe_cards", "nomikais"
  add_foreign_key "nomikai_vibe_cards", "vibe_cards"
  add_foreign_key "nomikais", "users"
  add_foreign_key "participants", "invitations"
  add_foreign_key "participants", "nomikais"
  add_foreign_key "participants", "users", on_delete: :nullify
  add_foreign_key "swipes", "nomikai_vibe_cards"
  add_foreign_key "swipes", "participants"
end
