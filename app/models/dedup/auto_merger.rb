# Post-sync pass that merges the duplicate pairs nobody needs to review:
# an imported (monarch) row and its provider-fed twin on the SAME account —
# same amount+currency, at most a day apart, near-identical names.
#
# Everything looser stays in the manual review queue. The provider row
# always wins (it keeps being re-delivered and enriched by sync), and two
# provider rows are never auto-merged — only a `source=monarch` loser is
# safe to remove, because the imported archive never re-delivers.
class Dedup::AutoMerger
  MAX_DATE_GAP_DAYS = 1
  MIN_NAME_SCORE = 0.8

  attr_reader :family

  def initialize(family:)
    @family = family
  end

  # Returns the number of pairs merged. Never raises into the caller — a
  # failed dedup pass must not fail a sync.
  def call
    return 0 unless family.auto_merge_duplicates?

    merged = 0

    scanner.candidates.each do |candidate|
      next unless auto_mergeable?(candidate)

      merged += 1 if Dedup::Merger.for_candidate(candidate).merge!
    end

    log_result(merged)
    merged
  rescue => e
    Rails.logger.error("Dedup::AutoMerger failed for family #{family.id}: #{e.class}: #{e.message}")
    0
  end

  private
    def scanner
      @scanner ||= Dedup::Scanner.new(
        family: family,
        date_window: MAX_DATE_GAP_DAYS,
        min_name_score: MIN_NAME_SCORE
      )
    end

    # Cross-source, same account, provider row survives — and the loser must
    # be an imported row. The amount/currency/date/name thresholds already
    # come from the scanner's filters.
    def auto_mergeable?(candidate)
      candidate.same_account? &&
        candidate.loser.source == Monarch::Importer::SOURCE
    end

    def log_result(merged)
      Rails.logger.info("Dedup::AutoMerger family=#{family.id} merged=#{merged} scanned=#{scanner.candidates.size}")

      DebugLogEntry.capture(
        category: "provider_sync",
        level: "info",
        message: "Auto-merged #{merged} cross-source duplicate pair(s) after provider sync",
        source: "dedup:auto_merger",
        family: family,
        metadata: { merged: merged, scanned: scanner.candidates.size }
      )
    end
end
