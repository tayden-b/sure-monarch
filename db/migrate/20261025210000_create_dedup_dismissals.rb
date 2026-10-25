# Persists "not a duplicate" decisions for Dedup::Scanner candidate pairs so
# a dismissed pair never resurfaces. The pair key is built from each entry's
# stable identity (source:external_id) rather than its entry uuid, so the
# dismissal survives a re-import or re-sync that recreates the row with a
# fresh uuid.
class CreateDedupDismissals < ActiveRecord::Migration[8.1]
  def change
    create_table :dedup_dismissals, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :pair_key, null: false
      t.timestamps

      t.index %i[family_id pair_key], unique: true, name: "idx_dedup_dismissals_unique"
    end
  end
end
