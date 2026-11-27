class AddRestaurantDecisionToNomikais < ActiveRecord::Migration[8.1]
  def up
    add_column :nomikais, :decision_state, :string, default: "pending", null: false
    add_column :nomikais, :decision_round, :integer, default: 0, null: false
    add_column :nomikais, :confirmed_at, :datetime
    # Old matches were saved before confirmation existed. Do not mark them confirmed.
    execute "UPDATE nomikais SET decision_state = 'legacy' WHERE matches_found_at IS NOT NULL"
    # Reopen at most the newest previously open match per host, if no active plan exists.
    execute <<~SQL
      UPDATE nomikais SET decision_state = 'pending' WHERE id IN (
        SELECT DISTINCT ON (n.user_id) n.id FROM nomikais n
        WHERE n.status = 'open' AND n.decision_state = 'legacy'
          AND NOT EXISTS (SELECT 1 FROM nomikais a WHERE a.user_id = n.user_id AND a.status = 'open' AND a.matches_found_at IS NULL)
        ORDER BY n.user_id, n.matches_found_at DESC, n.id DESC
      )
    SQL
    remove_index :nomikais, name: "index_nomikais_one_ongoing_per_user"
    add_index :nomikais, :user_id, unique: true,
              where: "status = 'open' AND decision_state IN ('pending', 'voting', 'rejected')", name: "index_nomikais_one_ongoing_per_user"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Decision and historical states cannot safely be reconstructed"
  end
end
