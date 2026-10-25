# One run of the Monarch archive importer (see Monarch::Importer).
#
# `report` stores the reconciliation report computed at the end of the run.
# `reference_documents` stores archive content that is useful for reference but
# must not enter ledger tables: settings_documents and credit_scores.
class MonarchImport < ApplicationRecord
  STATUSES = %w[pending running complete failed].freeze

  belongs_to :family

  validates :status, inclusion: { in: STATUSES }

  scope :ordered, -> { order(created_at: :desc) }

  def complete?
    status == "complete"
  end
end
