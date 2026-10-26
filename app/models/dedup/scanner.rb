# Family-level duplicate-candidate scan — the post-import/post-sync pass
# that surfaces likely duplicates the same-account pending-vs-posted
# machinery cannot see (e.g. a `source=monarch` import row and a Plaid
# redelivery of the same charge, or the same charge on two cards).
#
# A pair is a candidate when it passes ALL of:
#   * same currency and equal |amount| (sign-agnostic bucket)
#   * |date gap| <= date_window (default ±3 days)
#   * normalized name similarity >= min_name_score (Dedup::NameNormalizer)
#   * not transfer-shaped: opposite-sign rows on different accounts are the
#     two legs of one movement, not a duplicate
#   * not two rows of one store's own feed — when both entries carry the
#     store's `external_id` and `a.source == b.source`, they are distinct
#     real transactions by definition (the provider already dedups its
#     feed). Turned off by `include_same_source` for e.g. CSV-double-upload
#     cleanup.
#   * not previously dismissed (Dedup::Dismissal)
#
# Results are scored, sorted by confidence, and capped at `limit` so a
# large archive stays reviewable.
class Dedup::Scanner
  DEFAULT_DATE_WINDOW = 3
  DEFAULT_MIN_NAME_SCORE = 0.5
  DEFAULT_LIMIT = 200

  attr_reader :family, :account, :date_window, :min_name_score, :limit

  def initialize(family:, account: nil, date_window: DEFAULT_DATE_WINDOW,
                 min_name_score: DEFAULT_MIN_NAME_SCORE, limit: DEFAULT_LIMIT,
                 include_dismissed: false, include_same_source: false)
    @family = family
    @account = account
    @date_window = date_window
    @min_name_score = min_name_score
    @limit = limit
    @include_dismissed = include_dismissed
    @include_same_source = include_same_source
  end

  def candidates
    @candidates ||= compute_candidates
  end

  # Dry-run/report shape for `monarch:dedup` and the import hook.
  def summary
    {
      total: candidates.size,
      by_account: candidates.group_by { |c| c.account.name }.transform_values(&:size),
      by_confidence: candidates.group_by(&:confidence).transform_values(&:size)
    }
  end

  private
    def compute_candidates
      dismissed = dismissed_pair_keys
      found = []

      buckets.each_value do |bucket|
        next if bucket.size < 2

        bucket.combination(2) do |a, b|
          next if dismissed.include?(Dedup.pair_key(a, b))
          next if same_store_twins?(a, b)
          next if transfer_shaped?(a, b)

          gap = (a.date - b.date).abs.to_i
          next if gap > date_window

          name_score = name_score_for(a, b)
          next if name_score < min_name_score

          found << Dedup::Candidate.new(
            entry_a: a,
            entry_b: b,
            score: score_for(a, b, gap, name_score),
            name_score: name_score,
            date_gap_days: gap
          )
        end
      end

      found
        .sort_by { |c| [ -c.score, c.entry_a.date, c.entry_a.id, c.entry_b.id ] }
        .first(limit)
    end

    # Buckets by currency + |amount| — the cheap pre-filter, and the
    # "amount equality post sign-flip" requirement.
    def buckets
      scope = Entry.where(entryable_type: "Transaction")
                   .joins(:account)
                   .where(accounts: { family_id: family.id })
                   .where(parent_entry_id: nil)
                   .excluding_split_parents
      scope = scope.where(account_id: account.id) if account
      # preload (not includes): entryable is polymorphic — only Transactions
      # are in scope here, so it resolves to one transactions preload +
      # merchant/tags on them.
      scope = scope.preload(:account, entryable: [ :merchant, :tags ])
      scope.group_by { |e| [ e.currency, e.amount.abs ] }
    end

    def dismissed_pair_keys
      return Set.new if @include_dismissed
      @dismissed_pair_keys ||= Dedup::Dismissal.where(family: family).pluck(:pair_key).to_set
    end

    # Two rows from one store's own feed — each carrying that store's id —
    # are two real transactions by definition: Monarch, Plaid & co. already
    # dedup what they deliver, so a same-source pair of external_ids is two
    # separate charges (daily transfers, repeated card swipes). Rows missing
    # provenance (manual/CSV) stay eligible — they have no id to lean on.
    def same_store_twins?(a, b)
      return false if @include_same_source

      a.source.present? && a.external_id.present? &&
        b.source.present? && b.external_id.present? &&
        a.source == b.source
    end

    # Opposite-direction rows on different accounts are the two legs of one
    # real movement (a transfer between the user's own accounts), not a
    # duplicate of each other.
    def transfer_shaped?(a, b)
      a.account_id != b.account_id && (a.amount.negative? != b.amount.negative?)
    end

    def name_score_for(a, b)
      base = Dedup::NameNormalizer.similarity(a.name, b.name)
      merchant_a, merchant_b = a.entryable.merchant_id, b.entryable.merchant_id
      merchant_a.present? && merchant_a == merchant_b ? [ base, 0.8 ].max : base
    end

    def score_for(a, b, gap, name_score)
      date_score = 1.0 - (gap.to_f / (date_window + 1))
      account_score = a.account_id == b.account_id ? 1.0 : 0.5
      # Different provenance is weak corroboration the rows describe the
      # same real-world charge. A same-source score now only sees pairs
      # where at least one side lacks provenance (manual/CSV rows) — or
      # every same-source pair when `include_same_source` is on.
      source_score = a.source == b.source ? 0.6 : 1.0
      sign_score = a.amount.negative? == b.amount.negative? ? 1.0 : 0.3

      (100 * (0.40 * name_score + 0.25 * date_score +
              0.15 * account_score + 0.10 * source_score + 0.10 * sign_score)).round(1)
    end
end
