# A user decision that a Dedup::Scanner pair is NOT a duplicate. The pair
# key derives from each entry's stable `source:external_id` identity (not
# its uuid), so the pair stays dismissed across re-imports/re-syncs that
# destroy and recreate the rows.
class Dedup::Dismissal < ApplicationRecord
  self.table_name = "dedup_dismissals"

  belongs_to :family

  validates :pair_key, presence: true, uniqueness: { scope: :family_id }

  def self.dismiss!(family:, entry_a:, entry_b:)
    create_or_find_by!(family: family, pair_key: Dedup.pair_key(entry_a, entry_b))
  end
end
