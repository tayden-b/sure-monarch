# Cross-source duplicate detection and merging.
#
# After a bulk history import (e.g. `monarch:import`) a live provider feed
# re-delivers the same real transactions for its backfill window, and the
# same-account pending-vs-posted machinery
# (Transaction#pending_duplicate_candidates) cannot see them. Dedup scans
# the whole family ledger, surfaces scored candidate pairs
# (Dedup::Scanner), lets a human merge them (Dedup::Merger) with
# provider-rows preferred over imported ones, and remembers "not a
# duplicate" decisions (Dedup::Dismissal).
module Dedup
  # Merge-winner preference: provider-backed rows beat imported ones
  # because they keep being re-delivered and enriched by sync; imported
  # (monarch) provenance beats rows with no provenance at all. Pending rows
  # always lose — they are provisional by definition.
  def self.source_rank(entry)
    tx = entry.entryable
    pending = tx.is_a?(Transaction) && tx.pending?
    base = if entry.source.present? && entry.source != Monarch::Importer::SOURCE
      2
    elsif entry.source == Monarch::Importer::SOURCE
      1
    else
      0
    end
    [ pending ? 0 : 1, base ]
  end

  # The entry that should survive a merge of the pair.
  def self.preferred_entry(entry_a, entry_b)
    cmp = source_rank(entry_a) <=> source_rank(entry_b)
    return entry_a if cmp&.positive?
    return entry_b if cmp&.negative?
    # Tie: keep the older row — first-seen is likelier to carry user context.
    entry_a.created_at <= entry_b.created_at ? entry_a : entry_b
  end

  # Stable identity used in pair keys: provider/monarch external_ids don't
  # change when an entry is recreated, so dismissals survive re-imports.
  def self.stable_key(entry)
    if entry.source.present? && entry.external_id.present?
      "#{entry.source}:#{entry.external_id}"
    else
      "entry:#{entry.id}"
    end
  end

  def self.pair_key(entry_a, entry_b)
    [ stable_key(entry_a), stable_key(entry_b) ].sort.join("|")
  end
end
