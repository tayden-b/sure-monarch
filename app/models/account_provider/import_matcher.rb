# Finds the one unlinked, imported account a newly-linked provider account
# should attach to, instead of creating a duplicate next to it.
#
# When a provider account (Plaid, Coinbase, Kraken) has no AccountProvider
# link yet, first processing would otherwise build a brand-new Account beside
# the imported one — leaving the imported history stranded and the feed on an
# empty account. Families that ran `monarch:import` already hold accounts
# whose display names and MonarchSourceMapping payloads identify them; this
# matcher attaches the feed to those instead.
#
# Matching is deliberately conservative: a rule must produce exactly one
# candidate or we move on — a wrong attach rewrites a user's account, while
# a missed attach only creates a duplicate the user can fix manually via
# "Link provider" / `providers:attach`.
class AccountProvider::ImportMatcher
  # mask_in_name     — provider mask appears as the trailing "(...1234)" of
  #                    the imported display name, same accountable class
  # payload_mask     — the account's MonarchSourceMapping payload mask equals
  #                    the provider mask, same accountable class
  # plaid_institution — exactly one unlinked account of that class whose
  #                    Monarch payload institution.plaidInstitutionId equals
  #                    the provider item's institution_id
  # institution_name — exactly one unlinked account of that class carrying the
  #                    provider brand name (crypto exchanges have no Plaid id)
  RULES = %i[mask_in_name payload_mask plaid_institution institution_name].freeze

  Result = Struct.new(:account, :rule, keyword_init: true)

  def initialize(family:, accountable_class:, mask: nil, plaid_institution_id: nil, institution_name: nil)
    @family = family
    @accountable_class = accountable_class
    @mask = mask.presence
    @plaid_institution_id = plaid_institution_id.presence
    @institution_name = institution_name.presence
  end

  # Returns a Result when a rule yields exactly one candidate, else nil.
  def match
    RULES.each do |rule|
      candidates = candidates_for(rule)
      return Result.new(account: candidates.first, rule: rule) if candidates.one?
    end
    nil
  end

  private
    attr_reader :family, :accountable_class, :mask, :plaid_institution_id, :institution_name

    def candidates_for(rule)
      case rule
      when :mask_in_name
        return [] unless mask
        unlinked_candidates.select { |account| name_mask(account.name) == mask }
      when :payload_mask
        return [] unless mask
        unlinked_candidates.select { |account| monarch_payload(account)["mask"].presence == mask }
      when :plaid_institution
        return [] unless plaid_institution_id
        unlinked_candidates.select do |account|
          monarch_payload(account).dig("institution", "plaidInstitutionId") == plaid_institution_id
        end
      when :institution_name
        return [] unless institution_name
        unlinked_candidates.select { |account| account.institution_name.to_s.casecmp?(institution_name) }
      else
        []
      end
    end

    # Imported accounts are unlinked by definition (no provider rows, no
    # legacy ids). Disabled accounts are a deliberate end-state we must not
    # revive, and pending_deletion is mid-destroy — neither can take a feed.
    def unlinked_candidates
      @unlinked_candidates ||= family.accounts
        .manual
        .where(accountable_type: accountable_class.name)
        .where.not(status: [ :disabled, :pending_deletion ])
        .to_a
    end

    def monarch_payload(account)
      monarch_payloads[account.id] || {}
    end

    def monarch_payloads
      @monarch_payloads ||= MonarchSourceMapping
        .where(
          family_id: family.id,
          collection: "accounts",
          record_type: "Account",
          record_id: unlinked_candidates.map(&:id)
        )
        .index_by(&:record_id)
        .transform_values { |mapping| mapping.payload || {} }
    end

    # "SoFi Checking (...7564)" -> "7564". Only parenthesised groups made of
    # mask punctuation and digits qualify — "Fund (Series B)" must not.
    def name_mask(name)
      name.to_s[/\(([\d.·•…\s]+)\)\s*\z/, 1]&.delete("^0-9")
    end
end
