# Normalizes provider/ledger transaction descriptions so cosmetic bank
# decoration ("SQ *", "TST*", channel prefixes, store/register numbers)
# does not hide a duplicate, and scores how similar two descriptions are.
class Dedup::NameNormalizer
  # Channel/card/provider boilerplate tokens. Removed anywhere in the name
  # because banks prefix differently ("SQ *Joe's", "TST* Joe's").
  DECOR_TOKENS = %w[
    sq tst sp pp intl pmt pmts chk dc pos ach www web card debit credit
    checkcard purchase visa mastercard amex disc discover bp wd withdrawal
    payment transfer transaction p2p applepay gpay googlepay pending
  ].freeze

  class << self
    # Lowercased, alnum-only, decor tokens and long digit runs stripped.
    def call(name)
      name.to_s
          .gsub(/[''`]/, "")
          .gsub(/[^[:alnum:][:space:]]/, " ")
          .gsub(/\b(?:#{DECOR_TOKENS.join("|")})\b/i, " ")
          .gsub(/\b\d{3,}\b/, " ")
          .gsub(/[[:space:]]+/, " ")
          .strip
          .downcase
    end

    # 0.0–1.0 similarity: exact normalized match, containment, or a
    # token-overlap (Jaccard) score.
    def similarity(name_a, name_b)
      a, b = call(name_a), call(name_b)
      return 1.0 if a == b && a.present?
      return 0.0 if a.blank? || b.blank?

      ta, tb = a.split.to_set, b.split.to_set
      jaccard = (ta & tb).size.fdiv((ta | tb).size)
      containment = a.include?(b) || b.include?(a) ? (ta & tb).size.fdiv([ ta.size, tb.size ].min) : 0.0
      [ jaccard, containment ].max
    end
  end
end
