# Reads a Monarch export archive directory.
#
# Layout (see docs/monarch-import/SCHEMA.md):
#   <archive>/import/<collection>.json  — consolidated records, top-level list
#   <archive>/VALIDATION.json           — exporter's own validation summary
#   <archive>/monarch.sqlite            — same data in SQLite form (not read)
#
# The `import/` JSON files are authoritative: they hold the consolidated
# records Monarch produced after its own dedup pass. `monarch.sqlite` is not
# read — it carries the same collections, plus raw request payloads we do not
# need (IMPORT-RULES rule 5: empty successful responses are not errors).
class Monarch::Archive
  class Error < StandardError; end

  attr_reader :root

  # Collections the importer knows about, in dependency order.
  LEDGER_COLLECTIONS = %w[
    category_groups categories tags accounts merchants transactions
    transaction_tags balance_history holdings rules recurring_streams
    budget_totals budget_months goals
  ].freeze

  # Stored for reference only (never into ledger tables).
  REFERENCE_COLLECTIONS = %w[settings_documents credit_scores].freeze

  # Derived series / auxiliary data that is intentionally not imported.
  SKIPPED_COLLECTIONS = %w[
    aggregate_holdings attachments equity_grants net_worth_daily
    portfolio_performance provenance tax_lots transaction_activity
  ].freeze

  def initialize(root)
    @root = Pathname.new(root.to_s)
    unless import_dir.directory?
      raise Error, "No import/ directory found at #{root} — expected the Monarch export archive layout " \
                   "(import/<collection>.json). See docs/monarch-import/SCHEMA.md."
    end
  end

  # Raw records for a collection (array of hashes). Missing file or a file
  # whose top level is not a list counts as empty, matching SCHEMA.md.
  def records(collection)
    file = import_dir.join("#{collection}.json")
    return [] unless file.exist?

    data = JSON.parse(file.read)
    data.is_a?(Array) ? data : Array(data)
  rescue JSON::ParserError => e
    raise Error, "Could not parse #{file}: #{e.message}"
  end

  def collection_names
    @collection_names ||= import_dir.children.select { |p| p.extname == ".json" }
                                     .map { |p| p.basename(".json").to_s }
                                     .sort
  end

  def validation
    file = root.join("VALIDATION.json")
    file.exist? ? JSON.parse(file.read) : nil
  end

  def name
    root.basename.to_s
  end

  private
    def import_dir
      root.join("import")
    end
end
