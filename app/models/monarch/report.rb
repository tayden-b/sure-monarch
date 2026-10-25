# Reconciliation report for one import run.
#
# Per collection: how many records the archive held, how many were created,
# updated, or skipped (with a reason per skip). Plus a per-account comparison
# of transaction totals — the archive's signed Monarch amounts vs the Sure
# entries written (Sure stores the inverse sign: positive = expense).
class Monarch::Report
  CollectionStats = Struct.new(:archive_count, :created, :updated, :skipped, :errors, keyword_init: true)

  attr_reader :collections, :account_totals, :warnings

  def initialize
    @collections = {}
    @account_totals = {} # monarch account id => { name:, archive_total:, sure_total: }
    @warnings = []
  end

  def stats_for(collection)
    collections[collection] ||= CollectionStats.new(archive_count: 0, created: 0, updated: 0, skipped: {}, errors: [])
  end

  def archive_count(collection, n)
    stats_for(collection).archive_count = n
  end

  def created(collection) = stats_for(collection).created += 1
  def updated(collection) = stats_for(collection).updated += 1

  def skipped(collection, reason)
    skips = stats_for(collection).skipped
    skips[reason] = (skips[reason] || 0) + 1
  end

  def error(collection, monarch_id, message)
    stats_for(collection).errors << { monarch_id: monarch_id, message: message }
  end

  def record_account_total(monarch_account_id, name:, archive_total:)
    account_totals[monarch_account_id] = {
      name: name,
      archive_total: archive_total.to_d,
      sure_total: 0.to_d
    }
  end

  def to_h
    {
      "collections" => collections.transform_values do |s|
        {
          "archive_count" => s.archive_count,
          "created" => s.created,
          "updated" => s.updated,
          "skipped" => s.skipped,
          "errors" => s.errors
        }
      end,
      "account_totals" => account_totals.transform_values do |t|
        { "name" => t[:name], "archive_total" => t[:archive_total].to_s, "sure_total" => t[:sure_total].to_s }
      end,
      "warnings" => warnings
    }
  end

  def to_text
    lines = []
    lines << "collection".ljust(24) + "archive".rjust(8) + "created".rjust(8) + "updated".rjust(8) + "skipped".rjust(8)
    lines << "-" * 56
    collections.each do |name, s|
      skipped_total = s.skipped.values.sum
      lines << name.ljust(24) + s.archive_count.to_s.rjust(8) + s.created.to_s.rjust(8) +
               s.updated.to_s.rjust(8) + skipped_total.to_s.rjust(8)
      s.skipped.each do |reason, n|
        lines << "  └─ #{reason}: #{n}"
      end
      s.errors.each do |e|
        lines << "  ! #{e[:monarch_id]}: #{e[:message]}"
      end
    end

    if account_totals.any?
      lines << ""
      lines << "transaction totals per account (Sure sign convention: positive = expense)"
      lines << "account".ljust(32) + "archive".rjust(14) + "imported".rjust(14) + "diff".rjust(12)
      lines << "-" * 72
      account_totals.each_value do |t|
        diff = t[:archive_total] + t[:sure_total] # Sure total should equal -archive total
        flag = diff.abs > 0.005 ? "  <-- MISMATCH" : ""
        lines << t[:name].truncate(30).ljust(32) + t[:archive_total].to_s("F").rjust(14) +
                 t[:sure_total].to_s("F").rjust(14) + diff.to_s("F").rjust(12) + flag
      end
    end

    if warnings.any?
      lines << ""
      warnings.each { |w| lines << "warning: #{w}" }
    end

    lines.join("\n")
  end
end
