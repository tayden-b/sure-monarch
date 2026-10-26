# Imports a Monarch Money export archive into Sure.
#
# Implements docs/monarch-import/IMPORT-RULES.md:
#   1. Monarch IDs are opaque strings — every record lands in
#      monarch_source_mappings (collection, monarch_id -> Sure record), so a
#      re-run updates instead of duplicating.
#   2. Import order: category groups + categories -> tags -> accounts ->
#      merchants -> goals -> transactions -> balance_history -> holdings ->
#      rules -> recurring_streams -> budgets.
#   3. Signs/nulls/precision preserved. Note the sign *conventions* differ:
#      Monarch stores expenses as negative, Sure stores expenses as positive
#      (entries.amount >= 0 is an outflow — see Entry#type). Transaction
#      amounts are therefore negated once; the per-account totals in the
#      reconciliation report verify this. Liability balances (credit cards,
#      loans) are stored positive in Sure, matching Account#create_from_*
#      provider code — Monarch's signedBalance is abs()'d exactly once.
#   4. No heuristic dedup: import_transaction runs with
#      allow_heuristic_matching: false so transactions only match on their
#      Monarch external_id.
#   5. The archive has no splits/notes/attachments; nothing special needed.
#   6. Derived series (net_worth_daily, portfolio_performance,
#      transaction_activity, aggregate_holdings, provenance) never enter
#      ledger tables — they are counted as skipped in the report.
#   7. Every source record is stored in its mapping's payload for provenance.
#
# Pending / needsReview are stored under transactions.extra["monarch"]; Sure's
# pending machinery reads it because "monarch" is in
# Transaction::PENDING_PROVIDERS.
class Monarch::Importer
  SOURCE = "monarch"

  # Monarch (type.name, subtype.name) -> Sure accountable + subtype.
  # Anything unmapped falls back to isAsset ? OtherAsset : OtherLiability and
  # is reported as a warning.
  DEPOSITORY_SUBTYPES = Depository::SUBTYPES.freeze
  INVESTMENT_SUBTYPE_MAP = {
    "brokerage" => "brokerage", "cash_management" => "cash_management",
    "ira" => "ira", "roth" => "roth_ira", "sep_ira" => "sep_ira",
    "simple_ira" => "simple_ira", "st_401k" => "401k", "401k" => "401k",
    "roth_401k" => "roth_401k", "403b" => "403b", "457b" => "457b",
    "tsp" => "tsp", "529_plan" => "529_plan",
    "health_savings_account" => "hsa", "hsa" => "hsa",
    "pension" => "pension", "ugma" => "ugma", "utma" => "utma"
  }.freeze

  # Monarch security.type -> Sure asset_sub_class.
  SECURITY_TYPE_MAP = {
    "equity" => "stock", "etf" => "etf", "cryptocurrency" => "cryptocurrency",
    "cash" => "cash", "mutual_fund" => "mutual_fund", "other" => nil,
    "bond" => "bond", "option" => nil, "derivative" => nil
  }.freeze

  # Monarch merchantCriteria/merchantNameCriteria operator -> Sure text operator.
  TEXT_OPERATOR_MAP = {
    "contains" => "like", "not_contains" => "not_like", "does_not_contain" => "not_like",
    "is" => "=", "is_not" => "!=", "equals" => "=", "not_equals" => "!=",
    "eq" => "=", "neq" => "!=", "ne" => "!=", "not_eq" => "!=",
    "starts_with" => "like", "ends_with" => "like"
  }.freeze

  AMOUNT_OPERATOR_MAP = {
    "greater_than" => ">", "greater_than_or_equal" => ">=",
    "less_than" => "<", "less_than_or_equal" => "<=",
    "equal_to" => "=", "not_equal_to" => "!=",
    "equals" => "=", "greaterThan" => ">", "greaterThanOrEqual" => ">=",
    "lessThan" => "<", "lessThanOrEqual" => "<=", "equalTo" => "=",
    "eq" => "=", "neq" => "!=", "ne" => "!=", "gt" => ">", "gte" => ">=", "lt" => "<", "lte" => "<="
  }.freeze

  attr_reader :family, :archive, :dry_run, :report, :monarch_import

  def initialize(family:, archive_path:, dry_run: false, io: $stdout)
    @family = family
    @archive = Monarch::Archive.new(archive_path)
    @dry_run = dry_run
    @io = io
    @report = Monarch::Report.new
  end

  def run
    @monarch_import = family.monarch_imports.create!(
      status: "running", dry_run: dry_run, archive_name: archive.name
    )

    begin
      ActiveRecord::Base.transaction do
        import_category_groups_and_categories
        import_tags
        import_accounts
        import_merchants
        import_goals
        import_transactions
        import_balance_history
        anchor_accounts_without_history
        import_holdings
        import_rules
        import_recurring_streams
        import_budgets
        store_reference_documents
        record_skipped_collections
        compute_account_totals
        materialize_balances unless dry_run

        raise ActiveRecord::Rollback if dry_run
      end
    rescue => e
      monarch_import.update!(status: "failed", error: "#{e.class}: #{e.message}", report: report.to_h)
      DebugLogEntry.capture(
        category: "provider_sync",
        level: "error",
        message: "Monarch archive import failed",
        source: "monarch:import",
        provider_key: "monarch",
        family: family,
        metadata: { error_class: e.class.name, error: e.message, archive: archive.name, dry_run: dry_run }
      )
      raise
    end

    monarch_import.update!(status: "complete", report: report.to_h)
    @io.puts(report.to_text)
    monarch_import
  end

  private
    # Monarch external_ids this family already merged away via Dedup::Merger
    # (or a pending-merge). Read once per import; the survivors record them in
    # transactions.extra["manual_merge"]. Same read pattern the provider sync
    # engines use.
    def merged_away_monarch_ids
      sql = <<~SQL
        SELECT mj.value ->> 'merged_from_external_id' AS external_id
        FROM entries
        INNER JOIN accounts ON accounts.id = entries.account_id
        INNER JOIN transactions ON transactions.id = entries.entryable_id
        CROSS JOIN LATERAL jsonb_array_elements(
          CASE WHEN jsonb_typeof(transactions.extra -> 'manual_merge') = 'array'
               THEN transactions.extra -> 'manual_merge'
               ELSE '[]'::jsonb
          END
        ) AS mj (value)
        WHERE accounts.family_id = :family_id
          AND entries.entryable_type = 'Transaction'
          AND jsonb_typeof(mj.value) = 'object'
          AND mj.value ->> 'merged_from_external_id' IS NOT NULL
      SQL
      bound = ApplicationRecord.sanitize_sql([ sql, { family_id: family.id } ])
      Set.new(ApplicationRecord.connection.select_values(bound).map(&:to_s))
    end

    # ---------------------------------------------------------------- mapping

    def mapped_record_id(collection, monarch_id)
      return nil if monarch_id.blank?

      MonarchSourceMapping.find_by(
        family: family, collection: collection, monarch_id: monarch_id.to_s
      )&.record_id
    end

    def record_mapping!(collection, monarch_id, record, payload)
      MonarchSourceMapping.find_or_initialize_by(
        family: family, collection: collection, monarch_id: monarch_id.to_s
      ).tap do |m|
        m.record = record
        m.payload = payload
        m.save!
      end
    end

    def each_record(collection)
      records = archive.records(collection)
      report.archive_count(collection, records.size)
      records.each do |record|
        begin
          yield record
        rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
          report.error(collection, monarch_record_id(collection, record), e.message)
        end
      end
    end

    def monarch_record_id(collection, record)
      record["id"] || record["account_id"] || record.values_at("entity_id", "month").compact.join(":").presence || "?"
    end

    # ------------------------------------------------------------ categories

    def import_category_groups_and_categories
      group_record_ids = {}

      each_record("category_groups") do |g|
        group = category_group_for(g)
        group.name = g["name"]
        group.classification = g["type"].presence_in(CategoryGroup::CLASSIFICATIONS) || "expense"
        group.position = g["order"]
        group.color = normalized_group_color(g["color"])
        track(group, "category_groups") do
          group.save!
          group_record_ids[g["id"]] = group.id
          record_mapping!("category_groups", g["id"], group, g)
        end
      end

      each_record("categories") do |c|
        group_id = group_record_ids[c.dig("group", "id")] ||
                   mapped_record_id("category_groups", c.dig("group", "id"))
        group = group_id && family.category_groups.find_by(id: group_id)

        category = find_category_for(c, group)
        category.assign_attributes(
          category_group: group,
          color: group&.color.presence || normalized_color(nil, seed: c["name"]),
          lucide_icon: Category.suggested_icon(c["name"])
        )
        track(category, "categories") do
          category.save!
          record_mapping!("categories", c["id"], category, c)
        end
      end
    end

    # Monarch group ids are stable, so the mapping is authoritative on
    # re-import; otherwise match on name + classification so groups that
    # share a name but differ in type stay distinct.
    def category_group_for(g)
      mapped = family.category_groups.find_by(id: mapped_record_id("category_groups", g["id"]))
      mapped || family.category_groups.find_or_initialize_by(
        name: g["name"],
        classification: g["type"].presence_in(CategoryGroup::CLASSIFICATIONS) || "expense"
      )
    end

    # Group colors are optional in Monarch — preserve nulls rather than
    # inventing one (member categories still get a seeded color since
    # Category requires it).
    def normalized_group_color(color)
      color.to_s.match?(/\A#[0-9a-fA-F]{6}\z/) ? color : nil
    end

    # Category names are unique per family in Sure but not per group in
    # Monarch; disambiguate with the group name when two groups reuse a name.
    def find_category_for(c, group)
      category = family.categories.find_by(name: c["name"])
      if category.nil? || category.category_group_id == group&.id
        category || family.categories.build(name: c["name"], category_group: group)
      elsif group
        family.categories.find_or_initialize_by(name: "#{group.name} — #{c["name"]}", category_group_id: group.id)
      else
        family.categories.find_or_initialize_by(name: c["name"], category_group_id: nil)
      end
    end

    def normalized_color(color, seed:)
      return color if color.to_s.match?(/\A#[0-9a-fA-F]{6}\z/)

      Category::COLORS[seed.to_s.sum % Category::COLORS.size]
    end

    # ------------------------------------------------------------------ tags

    def import_tags
      each_record("tags") do |t|
        tag = family.tags.find_or_initialize_by(name: t["name"])
        tag.color = normalized_color(t["color"], seed: t["name"])
        track(tag, "tags") do
          tag.save!
          record_mapping!("tags", t["id"], tag, t)
        end
      end
    end

    # -------------------------------------------------------------- accounts

    def import_accounts
      each_record("accounts") do |r|
        accountable = build_accountable(r)
        unless accountable
          report.skipped("accounts", "unsupported_type:#{r.dig("type", "name")}/#{r.dig("subtype", "name")}")
          next
        end

        account_id = mapped_record_id("accounts", r["id"])
        account = account_id ? family.accounts.find_by(id: account_id) : nil
        report.warnings << "account #{r["id"]} (#{r["displayName"]}) has no balance in archive; imported at 0" if r["currentBalance"].nil? && r["displayBalance"].nil?

        attrs = account_attributes(r, accountable)
        if account
          # Never re-point accountable on an existing account — the monarch
          # type map is deterministic anyway, so a changed accountable means
          # the archive disagrees with a prior run; keep the original.
          account.assign_attributes(attrs.except(:accountable))
        else
          account = family.accounts.build(attrs.merge(accountable: accountable))
        end

        track(account, "accounts") do
          account.save!
          record_mapping!("accounts", r["id"], account, r)
        end
      end
    end

    def build_accountable(r)
      type = r.dig("type", "name").to_s
      subtype = r.dig("subtype", "name").to_s

      case type
      when "depository"
        Depository.new(subtype: DEPOSITORY_SUBTYPES.key?(subtype) ? subtype : "checking")
      when "credit"
        CreditCard.new(subtype: "credit_card")
      when "brokerage"
        if subtype == "cryptocurrency"
          Crypto.new(subtype: "exchange")
        elsif INVESTMENT_SUBTYPE_MAP.key?(subtype)
          Investment.new(subtype: INVESTMENT_SUBTYPE_MAP[subtype])
        else
          Investment.new(subtype: "brokerage")
        end
      when "loan", "mortgage"
        Loan.new(subtype: Loan::SUBTYPES.key?(subtype) ? subtype : (type == "mortgage" ? "mortgage" : "other"))
      when "real_estate"
        Property.new(subtype: Property::SUBTYPES.key?(subtype) ? subtype : "single_family_home")
      when "vehicle"
        Vehicle.new(subtype: Vehicle::SUBTYPES.key?(subtype) ? subtype : nil)
      when "other_asset"
        OtherAsset.new
      when "other_liability"
        OtherLiability.new
      else
        # Unknown Monarch type — honor the asset/liability flag rather than
        # dropping the account (rule: preserve data, document the fallback).
        (r["isLiability"] == false || r["isAsset"] == true) ? OtherAsset.new : OtherLiability.new
      end
    end

    LIABILITY_ACCOUNTABLES = %w[CreditCard Loan OtherLiability].freeze

    def account_attributes(r, accountable)
      raw_balance = r["displayBalance"].presence || r["currentBalance"]
      liability = LIABILITY_ACCOUNTABLES.include?(accountable.class.name)
      balance = raw_balance.to_d
      balance = balance.abs if liability

      cash_account = %w[Depository CreditCard Loan Property Vehicle OtherAsset OtherLiability].include?(accountable.class.name)

      deactivated_at = parse_date(r["deactivatedAt"])
      # Only `deactivatedAt` disables an account (stops sync). Monarch's
      # `isHidden`/`hideFromList` hide the row from lists while its balance
      # still counts, which maps to `hide_from_list` instead.
      disabled = deactivated_at.present?

      institution = r["institution"] || {}

      {
        name: r["displayName"].presence || "Monarch account",
        currency: family.currency,
        balance: balance,
        cash_balance: cash_account ? balance : 0,
        status: disabled ? "disabled" : "active",
        disabled_at: deactivated_at&.to_time,
        hide_from_list: r["isHidden"] == true || r["hideFromList"] == true,
        include_in_net_worth: r["includeInNetWorth"] != false,
        exclude_from_reports: r["hideTransactionsFromReports"] == true,
        hide_in_budget: r["hideInBudget"] == true,
        institution_name: institution["name"].presence,
        institution_domain: institution_domain(institution)
      }
    end

    def institution_domain(institution)
      url = institution["logo"].presence || institution["url"].presence
      return nil unless url

      URI.parse(url).host
    rescue URI::InvalidURIError
      nil
    end

    # ------------------------------------------------------------- merchants

    def import_merchants
      each_record("merchants") do |m|
        merchant = family.merchants.find_or_initialize_by(name: m["name"])
        merchant.logo_url ||= m["logoUrl"]
        track(merchant, "merchants") do
          merchant.save!
          record_mapping!("merchants", m["id"], merchant, m)
        end
      end
    end

    # ----------------------------------------------------------------- goals

    def import_goals
      each_record("goals") do |g|
        target = g["targetAmount"].to_d
        if target <= 0
          report.skipped("goals", "no_target_amount")
          next
        end

        goal_id = mapped_record_id("goals", g["id"])
        goal = goal_id ? family.goals.find_by(id: goal_id) : family.goals.new
        goal.assign_attributes(
          name: g["name"].presence || g["defaultName"].presence || "Monarch goal",
          target_amount: target,
          currency: family.currency,
          state: g["archivedAt"].present? ? "archived" : (g["completedAt"].present? ? "completed" : "active"),
          target_date: parse_date(g["estimatedCompletionMonth"])&.end_of_month,
          kind: "one_off"
        )

        # Goal validation requires >= 1 funding account at save time, so the
        # allocations must be built before a new goal is saved.
        allocations = Array(g["accountAllocations"]).filter_map do |alloc|
          account_id = mapped_record_id("accounts", alloc.dig("account", "id"))
          next unless account_id
          { account_id: account_id, allocated_amount: alloc["useEntireAccountBalance"] ? nil : (alloc["amount"] || alloc["currentAmount"]) }
        end
        allocations.each { |attrs| goal.goal_accounts.build(attrs) } if goal.new_record?

        track(goal, "goals") do
          goal.save!
          record_mapping!("goals", g["id"], goal, g)

          unless goal.previously_new_record?
            allocations.each do |attrs|
              ga = goal.goal_accounts.find_or_initialize_by(account_id: attrs[:account_id])
              ga.update!(allocated_amount: attrs[:allocated_amount])
            end
          end
        end
      end
    end

    # ----------------------------------------------------------- transactions

    def import_transactions
      tag_links = archive.records("transaction_tags")
      report.archive_count("transaction_tags", tag_links.size)
      tags_by_txn = tag_links.group_by { |l| l["transaction_id"] }
      linked_txns = Set.new
      merged_away_ids = merged_away_monarch_ids

      each_record("transactions") do |r|
        # A Monarch row the user already merged into a provider-backed entry
        # must not be resurrected by a re-import — the winner recorded the
        # loser's external_id in transactions.extra["manual_merge"].
        if merged_away_ids.include?(r["id"].to_s)
          report.skipped("transactions", "merged_duplicate")
          next
        end

        account_id = mapped_record_id("accounts", r.dig("account", "id"))
        account = account_id && family.accounts.find_by(id: account_id)
        unless account
          report.skipped("transactions", "unknown_account")
          next
        end

        extra = {
          SOURCE => {
            "pending" => r["pending"] == true,
            "needs_review" => r["needsReview"] == true,
            "review_status" => r["reviewStatus"],
            "data_provider_description" => r["dataProviderDescription"].presence || r["plaidName"],
            "is_manual" => r["isManual"] == true,
            "hidden_by_account" => r["hiddenByAccount"] == true
          }.compact
        }

        existed = account.entries.exists?(external_id: r["id"].to_s, source: SOURCE)
        entry = Account::ProviderImportAdapter.new(account).import_transaction(
          external_id: r["id"].to_s,
          amount: -r["amount"].to_d, # Monarch negative = expense; Sure positive = expense
          currency: family.currency,
          date: parse_date(r["date"]),
          name: r.dig("merchant", "name").presence || r["dataProviderDescription"].presence || r["plaidName"].presence || "Imported transaction",
          source: SOURCE,
          category_id: mapped_record_id("categories", r.dig("category", "id")),
          merchant: monarch_merchant_for(r["merchant"]),
          kind: r.dig("category", "group", "type") == "transfer" ? "funds_movement" : "standard",
          notes: r["notes"],
          extra: extra,
          allow_heuristic_matching: false
        )

        if entry
          excluded = r["hideFromReports"] == true || r["hiddenByAccount"] == true
          entry.update!(excluded: true) if excluded && !entry.excluded?

          linked_txns << r["id"]
          apply_tags(r, entry, tags_by_txn[r["id"]])

          record_mapping!("transactions", r["id"], entry, r)
          existed ? report.updated("transactions") : report.created("transactions")
        else
          report.skipped("transactions", "adapter_returned_nil")
        end
      rescue => e
        report.error("transactions", r["id"], "#{e.class}: #{e.message}")
      end

      # Links whose transactions never imported can't be applied.
      tag_links.each do |l|
        report.skipped("transaction_tags", "transaction_not_imported") unless linked_txns.include?(l["transaction_id"])
      end
    end

    # Embedded record["tags"] + transaction_tags links both apply; each link
    # counts in the report. Union with existing tag_ids so a re-run never
    # strips tags added in Sure after import.
    def apply_tags(r, entry, links)
      monarch_ids = Array(r["tags"]).map { |t| t.is_a?(Hash) ? t["id"] : t }
      existing_tag_ids = entry.transaction.tag_ids
      Array(links).each do |l|
        tag_id = mapped_record_id("tags", l["tag_id"])
        if tag_id
          monarch_ids << l["tag_id"]
          existing_tag_ids.include?(tag_id) ? report.updated("transaction_tags") : report.created("transaction_tags")
        else
          report.skipped("transaction_tags", "unmapped_tag")
        end
      end
      tag_ids = monarch_ids.uniq.filter_map { |mid| mapped_record_id("tags", mid) }
      all_ids = (entry.transaction.tag_ids + tag_ids).uniq
      entry.transaction.update!(tag_ids: all_ids) if tag_ids.any?
    end

    # Transactions/streams can reference merchants that never appeared in
    # merchants.json — create a stub so the link is preserved (and mappable).
    def monarch_merchant_for(m)
      return nil if m.blank? || m["id"].blank?

      id = mapped_record_id("merchants", m["id"])
      return family.merchants.find_by(id: id) if id
      return nil if m["name"].blank?

      family.merchants.create!(name: m["name"]).tap do |merchant|
        record_mapping!("merchants", m["id"], merchant, m)
        report.created("merchants")
      end
    end

    # --------------------------------------------------------- balance history

    # Each Monarch daily balance becomes a reconciliation Valuation entry:
    # Balance::ForwardCalculator honors a valuation on any date, so Sure's
    # materialized balances match Monarch's history and survive re-syncs.
    def import_balance_history
      each_record("balance_history") do |r|
        account_id = mapped_record_id("accounts", r["account_id"])
        account = account_id && family.accounts.find_by(id: account_id)
        unless account
          report.skipped("balance_history", "unknown_account")
          next
        end

        date = parse_date(r["date"])
        balance = r["signedBalance"].to_d
        balance = balance.abs if account.classification == "liability"

        external_id = "bh:#{r["account_id"]}:#{date}"
        entry = account.entries.find_or_initialize_by(source: SOURCE, external_id: external_id)

        if entry.new_record?
          clash = account.entries.find_by(date: date, entryable_type: "Valuation")
          if clash && !clash.entryable.reconciliation?
            report.skipped("balance_history", "date_anchored")
            next
          elsif clash
            entry = clash
            entry.source = SOURCE
            entry.external_id = external_id
          else
            entry.entryable = Valuation.new(kind: "reconciliation")
          end
        end

        was_new = entry.new_record?
        entry.assign_attributes(
          date: date,
          amount: balance,
          currency: account.currency,
          name: Valuation.build_reconciliation_name(account.accountable_type)
        )

        begin
          entry.save!
          record_mapping!("balance_history", "#{r["account_id"]}:#{date}", entry, r)
          was_new ? report.created("balance_history") : report.updated("balance_history")
        rescue ActiveRecord::RecordInvalid => e
          report.error("balance_history", "#{r["account_id"]}:#{date}", e.message)
        end
      end
    end

    # Accounts with no balance_history rows still carry a signedBalance. The
    # forward materializer recomputes balances from the opening anchor, which
    # an entry-less account lacks, and would overwrite the imported balance
    # with 0. Write one reconciliation valuation at the current date so every
    # imported account anchors to its Monarch balance.
    #
    # Not counted in the report: these are internal anchors and the
    # balance_history counts must keep matching the archive's row count.
    def anchor_accounts_without_history
      MonarchSourceMapping.where(family: family, collection: "accounts").find_each do |mapping|
        account = family.accounts.find_by(id: mapping.record_id)
        next unless account

        anchor = account.entries.find_by(
          source: SOURCE,
          external_id: "anchor:#{mapping.monarch_id}"
        )
        # Skip when real valuation entries exist (balance_history or a
        # provider's own valuations) — but not when only our own anchor does:
        # on re-import the anchor must re-anchor to the newer signedBalance or
        # materialization would revert the balance to the stale amount.
        real_valuations = account.entries.where(entryable_type: "Valuation")
        real_valuations = real_valuations.where.not(id: anchor.id) if anchor
        next if real_valuations.exists?

        entry = anchor || account.entries.build(
          source: SOURCE,
          external_id: "anchor:#{mapping.monarch_id}"
        )
        entry.entryable ||= Valuation.new(kind: "reconciliation")
        entry.assign_attributes(
          date: Date.current,
          amount: account.balance || 0,
          currency: account.currency,
          name: Valuation.build_reconciliation_name(account.accountable_type)
        )
        entry.save!
      end
    end

    # -------------------------------------------------------------- holdings

    # Monarch may hold several "cash" positions in one account (money-market
    # sweep funds, stablecoins, the raw currency line) but Sure has exactly one
    # cash security per account and a unique (account, security, date,
    # currency) index on holdings. Cash records are therefore summed into a
    # single holding per account keyed by `external_id: "cash:<monarch account
    # id>"`; every contributing Monarch id maps to that one holding.
    def import_holdings
      cash_positions = Hash.new { |h, k| h[k] = { account: nil, value: 0.to_d, records: [] } }

      each_record("holdings") do |r|
        monarch_account_id = r["account_id"] || r.dig("account", "id")
        account_id = mapped_record_id("accounts", monarch_account_id)
        account = account_id && family.accounts.find_by(id: account_id)
        unless account
          report.skipped("holdings", "unknown_account")
          next
        end

        if cash_security?(r)
          bucket = cash_positions[monarch_account_id.to_s]
          bucket[:account] = account
          bucket[:value] += r["value"].to_d
          bucket[:records] << r
          next
        end

        security = find_security(r, account)
        qty = r["quantity"].to_d
        value = r["value"].to_d
        price = (r["closingPrice"] || r.dig("security", "currentPrice") || (qty.zero? ? value : value / qty)).to_d
        date = parse_date(r["closingPriceUpdatedAt"]) || Date.current

        holding = account.holdings.find_or_initialize_by(external_id: r["id"].to_s)
        was_new = holding.new_record?
        holding.assign_attributes(
          security: security,
          qty: qty,
          price: price,
          amount: value,
          cost_basis: r["costBasis"],
          cost_basis_source: r["costBasis"].present? ? "provider" : nil,
          date: date,
          currency: family.currency
        )
        holding.save!
        record_mapping!("holdings", r["id"], holding, r)
        was_new ? report.created("holdings") : report.updated("holdings")
      end

      cash_positions.each do |monarch_account_id, bucket|
        account = bucket[:account]
        holding = account.holdings.find_or_initialize_by(external_id: "cash:#{monarch_account_id}")
        was_new = holding.new_record?
        holding.assign_attributes(
          security: Security.cash_for(account),
          qty: bucket[:value],
          price: 1,
          amount: bucket[:value],
          cost_basis: nil,
          cost_basis_source: nil,
          date: Date.current,
          currency: family.currency
        )
        holding.save!
        bucket[:records].each do |r|
          record_mapping!("holdings", r["id"], holding, r)
          was_new ? report.created("holdings") : report.updated("holdings")
        end
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
        bucket[:records].each { |r| report.error("holdings", r["id"], e.message) }
      end
    end

    def cash_security?(r)
      (r["security"] || {})["type"] == "cash"
    end

    def find_security(r, account)
      s = r["security"] || {}
      return Security.cash_for(account) if cash_security?(r)

      ticker = s["ticker"].presence || r["ticker"].presence || "MONARCH-#{s["id"] || r["id"]}"
      Security.find_or_initialize_by_ticker_and_exchange(ticker: ticker, exchange_operating_mic: nil).tap do |sec|
        sec.assign_attributes(
          name: s["name"].presence || ticker,
          asset_sub_class: SECURITY_TYPE_MAP[s["type"]],
          kind: "standard",
          offline: true
        )
        sec.save!
      end
    end

    # ------------------------------------------------------------------ rules

    # Monarch rules AND their criteria; Sure conditions are also ANDed.
    # Monarch's `order` is applied once everything imports via Rule.reorder!,
    # which writes dense 1..n positions (the field `Rule.ordered` and
    # first-match-wins application read); the order is also echoed in the rule
    # name so it still sorts sensibly when the list is viewed by name.
    def import_rules
      ordered = archive.records("rules")
      report.archive_count("rules", ordered.size)

      imported_ids = []
      ordered.sort_by { |r| r["order"] || Float::INFINITY }.each do |r|
        begin
          imported_ids << import_rule(r)&.id
        rescue => e
          report.error("rules", r["id"], "#{e.class}: #{e.message}")
        end
      end

      # Imported rules rank first in Monarch order; rules not in this list
      # (Sure-created ones, or a previously-imported rule skipped this run)
      # keep their relative order at the end.
      family.rules.reset
      Rule.reorder!(family, imported_ids.compact)
    end

    def import_rule(r)
      rule_id = mapped_record_id("rules", r["id"])
      # Rule.new (not family.rules.new) so a rule skipped below never lingers
      # unsaved in the association that Rule.reorder! walks afterwards.
      rule = (rule_id && family.rules.find_by(id: rule_id)) || Rule.new(family: family, resource_type: "transaction")
      rule.name = rule_name(r)
      rule.active = true

      rule.conditions.destroy_all if rule.persisted?
      rule.actions.destroy_all if rule.persisted?

      criteria_count = 0
      Array(r["merchantCriteria"]).each do |mc|
        add_condition(rule, "transaction_name", TEXT_OPERATOR_MAP[mc["operator"].to_s], mc["value"]) && criteria_count += 1
      end
      Array(r["merchantNameCriteria"]).each do |mc|
        add_condition(rule, "transaction_name", TEXT_OPERATOR_MAP[mc["operator"].to_s], mc["value"]) && criteria_count += 1
      end
      if (ac = r["amountCriteria"])
        op = AMOUNT_OPERATOR_MAP[ac["operator"].to_s]
        add_condition(rule, "transaction_amount", op, ac["value"].to_s) && criteria_count += 1 if op
        if ac["isExpense"] == true
          add_condition(rule, "transaction_type", "=", "expense")
        elsif ac["isExpense"] == false
          add_condition(rule, "transaction_type", "=", "income")
        end
      end
      Array(r["categoryIds"]).each do |cid|
        id = mapped_record_id("categories", cid)
        add_condition(rule, "transaction_category", "=", id.to_s) && criteria_count += 1 if id
      end
      Array(r["accountIds"]).each do |aid|
        id = mapped_record_id("accounts", aid)
        add_condition(rule, "transaction_account", "=", id.to_s) && criteria_count += 1 if id
      end

      if (cat_id = mapped_record_id("categories", r.dig("setCategoryAction", "id")))
        rule.actions.build(action_type: "set_transaction_category", value: cat_id.to_s)
      end
      tag_ids = Array(r["addTagsAction"]).filter_map { |t| mapped_record_id("tags", t["id"]) }
      rule.actions.build(action_type: "set_transaction_tags", value: tag_ids.join(",")) if tag_ids.any?
      rule.actions.build(action_type: "exclude_transaction", value: nil) if r["setHideFromReportsAction"] == true

      if criteria_count.zero? && rule.conditions.empty?
        report.skipped("rules", "no_mappable_criteria")
        return
      end

      was_new = rule.new_record?
      rule.save!
      record_mapping!("rules", r["id"], rule, r)
      was_new ? report.created("rules") : report.updated("rules")
      rule
    end

    def rule_name(r)
      hint = Array(r["merchantCriteria"]).first&.dig("value") ||
             Array(r["merchantNameCriteria"]).first&.dig("value") ||
             r.dig("setCategoryAction", "name") || r["id"].to_s
      "Monarch rule #{r["order"].presence || "?"}: #{hint}".truncate(250)
    end

    def add_condition(rule, type, operator, value)
      return false if operator.blank? || value.blank?

      rule.conditions.build(condition_type: type, operator: operator, value: value.to_s)
      true
    end

    # ------------------------------------------------------ recurring streams

    def import_recurring_streams
      each_record("recurring_streams") do |r|
        base = parse_date(r["baseDate"]) || Date.current
        rules_attrs = recurrence_rules_attrs(r["frequency"].to_s, base)
        unless rules_attrs
          report.skipped("recurring_streams", "unsupported_frequency:#{r["frequency"]}")
          next
        end

        rt_id = mapped_record_id("recurring_streams", r["id"])
        rt = rt_id ? family.recurring_transactions.find_by(id: rt_id) : family.recurring_transactions.new
        merchant_id = monarch_merchant_for(r["merchant"])&.id

        rt.assign_attributes(
          merchant_id: merchant_id,
          name: merchant_id ? nil : (r["name"].presence || r.dig("merchant", "name")),
          amount: -r["amount"].to_d, # same inversion as transactions
          currency: family.currency,
          expected_day_of_month: r["dayOfTheMonth"].presence || base.day,
          anchor_date: base,
          last_occurrence_date: base,
          next_expected_date: next_expected_date(r["frequency"].to_s, base),
          status: r["isActive"] == false ? "paused" : "active",
          bill_type: r["recurringType"] == "income" ? "income" : (r["recurringType"] == "transfer" ? "transfer" : "bill"),
          dedup_scope: "monarch:#{r["id"]}",
          manual: false
        )
        rt.recurrence_rules.destroy_all if rt.persisted?
        rules_attrs.each { |attrs| rt.recurrence_rules.build(attrs) }

        was_new = rt.new_record?
        rt.save!
        record_mapping!("recurring_streams", r["id"], rt, r)
        was_new ? report.created("recurring_streams") : report.updated("recurring_streams")
      rescue ActiveRecord::RecordInvalid => e
        report.error("recurring_streams", r["id"], e.message)
      end
    end

    # Monarch frequency string -> array of RecurrenceRule attr hashes.
    # Semi-monthly becomes two monthly rules (day D and day D+15, wrapped at
    # month end); daily has no Sure equivalent -> nil (skipped).
    def recurrence_rules_attrs(frequency, base)
      key = frequency.downcase.gsub(/[^a-z0-9]/, "")
      monthly = ->(interval, day = base.day) { { frequency: "monthly", interval: interval, day_of_month: day } }
      case key
      when "weekly"
        [ { frequency: "weekly", interval: 1, weekday: base.wday } ]
      when "everyotherweek", "biweekly", "every2weeks", "fortnightly"
        [ { frequency: "weekly", interval: 2, weekday: base.wday } ]
      when "semimonthly", "twicepermonth", "twiceamonth"
        other = base.day <= 15 ? [ base.day + 15, 28 ].min : base.day - 15
        [ monthly.call(1, [ base.day, 28 ].min), monthly.call(1, other) ]
      when "monthly", "everymonth", "every1month"
        [ monthly.call(1, [ base.day, 28 ].min) ]
      when "every2months", "bimonthly"
        [ monthly.call(2, [ base.day, 28 ].min) ]
      when "quarterly", "every3months"
        [ monthly.call(3, [ base.day, 28 ].min) ]
      when "every4months"
        [ monthly.call(4, [ base.day, 28 ].min) ]
      when "semiannually", "every6months", "twiceayear"
        [ monthly.call(6, [ base.day, 28 ].min) ]
      when "yearly", "annually", "everyyear", "every12months"
        [ { frequency: "yearly", interval: 1, month_of_year: base.month, day_of_month: base.day } ]
      end
    end

    def next_expected_date(_frequency, base)
      day = [ base.day, 28 ].min
      RecurringTransaction.calculate_next_expected_date_from_today(day) || base
    rescue
      base
    end

    # ---------------------------------------------------------------- budgets

    # budget_totals holds per-month planned totals; budget_months holds
    # per-entity (category) planned amounts. Only months that already exist —
    # i.e. not after the current month — are imported (task scope).
    def import_budgets
      totals_by_month = archive.records("budget_totals").index_by { |t| t["month"] }
      report.archive_count("budget_totals", totals_by_month.size)

      current_month = Date.current.beginning_of_month
      budgets_by_month = {}

      totals_by_month.each do |month_str, t|
        month = parse_month(month_str)
        if month.nil? || month > current_month
          report.skipped("budget_totals", "future_month")
          next
        end

        budget = find_or_build_budget(month)
        was_new = budget.new_record?
        budget.assign_attributes(
          budgeted_spending: t.dig("totalExpenses", "plannedAmount").to_d,
          expected_income: t.dig("totalIncome", "plannedAmount").to_d,
          currency: family.currency
        )
        budget.save!
        record_mapping!("budget_totals", month_str, budget, t)
        budgets_by_month[month_str] = budget
        was_new ? report.created("budget_totals") : report.updated("budget_totals")
      end

      each_record("budget_months") do |r|
        month_str = r["month"]
        month = parse_month(month_str)
        if month.nil? || month > current_month
          report.skipped("budget_months", "future_month")
          next
        end
        unless r["scope"] == "category"
          report.skipped("budget_months", "unsupported_scope:#{r["scope"]}")
          next
        end
        category_id = mapped_record_id("categories", r["entity_id"])
        unless category_id
          report.skipped("budget_months", "unknown_category")
          next
        end

        budget = budgets_by_month[month_str] || find_or_build_budget(month).tap(&:save!)
        bc = budget.budget_categories.find_or_initialize_by(category_id: category_id)
        was_new = bc.new_record?
        bc.assign_attributes(
          budgeted_spending: (r["plannedCashFlowAmount"] || r["plannedSetAsideAmount"]).to_d,
          rollover_enabled: r["rolloverType"].present?,
          currency: family.currency
        )
        bc.save!
        record_mapping!("budget_months", "#{month_str}:#{r["entity_id"]}", bc, r)
        was_new ? report.created("budget_months") : report.updated("budget_months")
      end
    end

    def find_or_build_budget(month)
      family.budgets.find_or_initialize_by(
        start_date: month.beginning_of_month,
        end_date: month.end_of_month,
        user_id: nil
      )
    end

    # ------------------------------------------------- reference + derived doc

    # settings_documents and credit_scores are kept as JSON blobs on the run
    # record — useful reference, never ledger data (task scope).
    def store_reference_documents
      docs = {
        "settings_documents" => archive.records("settings_documents"),
        "credit_scores" => archive.records("credit_scores")
      }
      docs.each { |name, rows| report.archive_count(name, rows.size) }
      unless dry_run
        monarch_import.update!(reference_documents: docs)
      end
      docs.each do |name, rows|
        rows.size.times { report.skipped(name, "reference_only") }
      end
    end

    def record_skipped_collections
      Monarch::Archive::SKIPPED_COLLECTIONS.each do |name|
        n = archive.records(name).size
        report.archive_count(name, n)
        n.times { report.skipped(name, "derived_or_not_applicable") }
      end
    end

    def compute_account_totals
      archive_totals = Hash.new { |h, k| h[k] = 0.to_d }
      archive.records("transactions").each do |r|
        archive_totals[r.dig("account", "id")] += r["amount"].to_d
      end

      MonarchSourceMapping.where(family: family, collection: "accounts").find_each do |m|
        account = family.accounts.find_by(id: m.record_id)
        next unless account

        sure_total = Entry.where(account_id: account.id, entryable_type: "Transaction", source: SOURCE)
                          .sum(:amount)
        report.record_account_total(m.monarch_id, name: account.name, archive_total: archive_totals[m.monarch_id])
        report.account_totals[m.monarch_id][:sure_total] = sure_total.to_d
      end
    end

    def materialize_balances
      MonarchSourceMapping.where(family: family, collection: "accounts").find_each do |m|
        account = family.accounts.find_by(id: m.record_id)
        next unless account

        begin
          # security_ids non-nil keeps Holding::Materializer from purging
          # imported holdings (Monarch archives carry no trade ledger, so the
          # forward purge would delete every non-provider holding).
          Balance::Materializer.new(account, strategy: :forward, security_ids: account.holdings.select(:security_id)).materialize_balances
        rescue => e
          report.warnings << "balance materialization failed for #{account.name}: #{e.message}"
        end
      end
    end

    # ---------------------------------------------------------------- helpers

    def parse_date(value)
      return nil if value.blank?

      Date.parse(value.to_s)
    rescue Date::Error
      nil
    end

    # "YYYY-MM" or "YYYY-MM-DD" -> first-of-month Date
    def parse_month(value)
      match = value.to_s.match(/(\d{4})-(\d{2})/)
      match && Date.new(match[1].to_i, match[2].to_i, 1)
    end

    # Yields around save! so created-vs-updated is counted correctly.
    def track(record, collection)
      was_new = record.new_record?
      yield
      was_new ? report.created(collection) : report.updated(collection)
    end
end
