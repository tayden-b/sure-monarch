# A typed bucket of categories, mirroring Monarch's category groups. The
# group's classification (income / expense / transfer) is authoritative for
# its members — Monarch has no per-category type — so saving a group's
# classification pushes it onto every member category, and assigning a
# category to a group overwrites its classification (see Category).
class CategoryGroup < ApplicationRecord
  CLASSIFICATIONS = %w[income expense transfer].freeze

  belongs_to :family
  has_many :categories, dependent: :nullify

  enum :classification, CLASSIFICATIONS.index_with { _1 }, scopes: false, validate: true

  validates :name, presence: true
  validates :color, format: { with: /\A#[0-9A-Fa-f]{6}\z/ }, allow_nil: true
  validates :position, numericality: { only_integer: true }, allow_nil: true

  # Monarch orders groups; groups without a position sort after ordered ones.
  scope :ordered, -> { order(:position, :name) }

  after_save :sync_category_classifications, if: :saved_change_to_classification?

  private
    # Members include subcategories — their group id is denormalized from the
    # parent by Category#inherit_classification_from_parent, so one update
    # covers the whole tree.
    def sync_category_classifications
      categories.update_all(classification: classification)
    end
end
