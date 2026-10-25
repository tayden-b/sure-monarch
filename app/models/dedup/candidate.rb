# One likely-duplicate pair produced by Dedup::Scanner. A value object —
# the review UI renders it, Dedup::Merger executes the merge, and
# `pair_key` identifies it in Dedup::Dismissal.
class Dedup::Candidate
  HIGH_CONFIDENCE = 80
  MEDIUM_CONFIDENCE = 55

  attr_reader :entry_a, :entry_b, :score, :name_score, :date_gap_days

  def initialize(entry_a:, entry_b:, score:, name_score:, date_gap_days:)
    @entry_a = entry_a
    @entry_b = entry_b
    @score = score
    @name_score = name_score
    @date_gap_days = date_gap_days
  end

  def id
    "#{entry_a.id}:#{entry_b.id}"
  end

  def confidence
    if score >= HIGH_CONFIDENCE
      :high
    elsif score >= MEDIUM_CONFIDENCE
      :medium
    else
      :low
    end
  end

  def pair_key
    @pair_key ||= Dedup.pair_key(entry_a, entry_b)
  end

  def same_account?
    entry_a.account_id == entry_b.account_id
  end

  def same_direction?
    entry_a.amount.negative? == entry_b.amount.negative?
  end

  # The entry the merge keeps (provider-sourced preferred — see Dedup).
  def winner
    @winner ||= Dedup.preferred_entry(entry_a, entry_b)
  end

  def loser
    winner == entry_a ? entry_b : entry_a
  end

  # The account to group under — the surviving side's account.
  def account
    winner.account
  end
end
