# Removes everything a Monarch::Importer run created, by deleting the Sure
# records pointed to by monarch_source_mappings, in FK-safe order, then the
# mappings and monarch_imports rows themselves.
#
# Only records that carry a monarch_source_mapping are touched — anything the
# user created or edited by hand is out of scope (edits made on top of an
# imported record are lost with it, which is the documented behavior).
class Monarch::Reverter
  # Deletion order matters: children before parents.
  COLLECTION_ORDER = %w[
    transactions transaction_tags balance_history holdings budget_months
    budget_totals recurring_streams rules goals accounts merchants tags
    categories category_groups
  ].freeze

  attr_reader :family, :report

  def initialize(family:, io: $stdout)
    @family = family
    @io = io
    @report = Hash.new(0)
  end

  def run
    ActiveRecord::Base.transaction do
      delete_taggings
      COLLECTION_ORDER.each { |collection| delete_collection(collection) }
      family.monarch_imports.delete_all
    end

    @report.each { |collection, n| @io.puts "#{collection}: deleted #{n}" }
    @report
  end

  private
    def mappings_for(collection)
      MonarchSourceMapping.where(family: family, collection: collection)
    end

    # Taggings on imported transactions are not mapped rows; drop them via the
    # transactions' mapped ids.
    def delete_taggings
      entry_ids = mappings_for("transactions").pluck(:record_id)
      txn_ids = Entry.where(id: entry_ids, entryable_type: "Transaction").pluck(:entryable_id)
      report["taggings"] = Tagging.where(taggable_type: "Transaction", taggable_id: txn_ids).delete_all
    end

    def delete_collection(collection)
      mappings = mappings_for(collection)
      ids = mappings.pluck(:record_id)
      return if ids.empty?

      klass = mappings.first.record_type.constantize
      report[collection] = klass.where(id: ids).destroy_all.size
      mappings.delete_all
    end
end
