# Executes a confirmed merge of a duplicate pair: `winner` survives,
# absorbs the loser's meaningful fields it lacks, records the merge in
# `transactions.extra["manual_merge"]` — the same convention the provider
# sync engines and `monarch:import` consult so the loser is not recreated —
# then the loser entry is destroyed. Mirrors the semantics of
# Transaction#merge_with_duplicate! for cross-source/cross-account pairs.
class Dedup::Merger
  def initialize(winner:, loser:)
    @winner = winner
    @loser = loser
  end

  def self.for_candidate(candidate)
    new(winner: candidate.winner, loser: candidate.loser)
  end

  # Returns true if the merge ran (or the pair was already gone).
  def merge!
    return false unless mergeable?

    Entry.transaction(requires_new: true) do
      return true unless lock_pair

      absorb_loser_fields
      record_manual_merge
      winner_tx.update!(needs_review: false) if winner_tx.needs_review?
      winner.mark_user_modified!
      loser.destroy!
    end
    true
  end

  private
    attr_reader :winner, :loser

    def winner_tx
      winner.entryable
    end

    def loser_tx
      loser.entryable
    end

    def mergeable?
      return false if winner.id == loser.id
      return false unless winner.entryable.is_a?(Transaction) && loser.entryable.is_a?(Transaction)
      return false if winner.split_parent? || winner.split_child? ||
                      loser.split_parent? || loser.split_child?
      true
    end

    # Locks both rows in deterministic id order. If a concurrent merge
    # already destroyed one, the pair is resolved — nothing to do.
    def lock_pair
      [ winner, loser ].sort_by(&:id).each do |entry|
        entry.lock!
      rescue ActiveRecord::RecordNotFound
        Rails.logger.info("Dedup merge: entry #{entry.id} already destroyed by a concurrent merge, skipping")
        return false
      end
      true
    end

    # The winner keeps its own values; blanks are filled from the loser
    # (category, merchant, notes), tags union, a "standard" winner takes
    # the loser's richer classification, and exclusion/reconciliation
    # state ORs forward.
    def absorb_loser_fields
      tx_attrs = {}
      tx_attrs[:category_id] = loser_tx.category_id if winner_tx.category_id.blank? && loser_tx.category_id.present?
      tx_attrs[:merchant_id] = loser_tx.merchant_id if winner_tx.merchant_id.blank? && loser_tx.merchant_id.present?
      tx_attrs[:kind] = loser_tx.kind if winner_tx.kind == "standard" && loser_tx.kind != "standard"
      winner_tx.update!(tx_attrs) if tx_attrs.any?

      union = (winner_tx.tag_ids + loser_tx.tag_ids).uniq
      winner_tx.tag_ids = union if union.size > winner_tx.tag_ids.size

      entry_attrs = {}
      entry_attrs[:notes] = loser.notes if winner.notes.blank? && loser.notes.present?
      entry_attrs[:excluded] = true if loser.excluded? && !winner.excluded?
      if winner.reconciled_at.blank? && loser.reconciled_at.present?
        entry_attrs[:reconciled_at] = loser.reconciled_at
        entry_attrs[:reconciled_by_statement_id] = loser.reconciled_by_statement_id
      end
      winner.update!(entry_attrs) if entry_attrs.any?
    end

    # Same `manual_merge` shape Transaction#merge_with_duplicate! writes —
    # provider processors and monarch:import read `merged_from_external_id`
    # to skip re-creating the losing row.
    def record_manual_merge
      record = {
        "merged_from_entry_id" => loser.id,
        "merged_from_external_id" => loser.external_id,
        "merged_at" => Time.current.iso8601,
        "source" => loser.source,
        "via" => "dedup"
      }
      prior = case winner_tx.extra["manual_merge"]
      when Array then winner_tx.extra["manual_merge"]
      when Hash then [ winner_tx.extra["manual_merge"] ]
      else []
      end
      winner_tx.update!(extra: winner_tx.extra.merge("manual_merge" => prior + [ record ]))
    end
end
