class AddPositionToRules < ActiveRecord::Migration[8.1]
  def up
    add_column :rules, :position, :integer
    add_index :rules, %i[family_id position]

    # Backfill in a stable order: oldest rule first, id as the tiebreak.
    execute <<~SQL
      WITH ranked AS (
        SELECT id,
               ROW_NUMBER() OVER (PARTITION BY family_id ORDER BY created_at, id) AS rn
        FROM rules
      )
      UPDATE rules
      SET position = ranked.rn
      FROM ranked
      WHERE rules.id = ranked.id
    SQL
  end

  def down
    remove_column :rules, :position
  end
end
