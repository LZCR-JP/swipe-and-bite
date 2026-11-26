class AddGatheringLifecycle < ActiveRecord::Migration[8.1]
  def up
    add_column :nomikais, :matches_found_at, :datetime
    # Candidate records are the only durable evidence of earlier successful searches.
    execute <<~SQL
      UPDATE nomikais n
      SET matches_found_at = c.first_match, status = 'closed'
      FROM (SELECT nomikai_id, MIN(created_at) AS first_match FROM candidates GROUP BY nomikai_id) c
      WHERE n.id = c.nomikai_id
    SQL
    execute <<~SQL
      UPDATE nomikais SET status = 'closed'
      WHERE status = 'open' AND matches_found_at IS NULL AND event_date <= CURRENT_TIMESTAMP
    SQL
    execute <<~SQL
      UPDATE nomikais SET status = 'closed'
      WHERE id IN (
        SELECT id FROM (
          SELECT id, ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY created_at DESC, id DESC) AS position
          FROM nomikais WHERE status = 'open' AND matches_found_at IS NULL
        ) ranked WHERE position > 1
      )
    SQL
    add_index :nomikais, :user_id, unique: true,
              where: "status = 'open' AND matches_found_at IS NULL", name: "index_nomikais_one_ongoing_per_user"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Previous open/closed states cannot be reconstructed safely"
  end
end
