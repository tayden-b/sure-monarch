# Maps one Monarch archive record (an opaque Monarch ID inside a named
# collection) to the Sure record it produced. The mapping is family-scoped so
# repeated imports of the same archive — or of a fresher export — update the
# same Sure records instead of duplicating them.
#
# `payload` keeps the raw Monarch record for provenance (IMPORT-RULES rule 7).
class MonarchSourceMapping < ApplicationRecord
  belongs_to :family
  belongs_to :record, polymorphic: true

  validates :collection, :monarch_id, presence: true
  validates :monarch_id, uniqueness: { scope: %i[family_id collection] }
end
