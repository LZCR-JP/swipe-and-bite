class AddUserToParticipants < ActiveRecord::Migration[8.1]
  def change
    add_reference :participants, :user, foreign_key: { on_delete: :nullify }, index: true
    add_index :participants, [:nomikai_id, :user_id], unique: true,
              where: "user_id IS NOT NULL", name: "index_participants_one_per_account"
  end
end
