require "test_helper"

class Monarch::ImporterTest < ActiveSupport::TestCase
  ARCHIVE = Rails.root.join("test/fixtures/files/monarch_archive").to_s

  setup do
    @family = families(:dylan_family)
    MonarchSourceMapping.where(family: @family).delete_all
    MonarchImport.where(family: @family).delete_all
  end

  def run_import(dry_run: false)
    Monarch::Importer.new(family: @family, archive_path: ARCHIVE, dry_run: dry_run, io: File.open(File::NULL, "w")).run
  end

  def mapping_for(collection, monarch_id)
    MonarchSourceMapping.find_by(family: @family, collection: collection, monarch_id: monarch_id)
  end

  test "imports all collections and writes a reconciliation report" do
    import = run_import

    assert import.complete?
    report = import.report["collections"]

    assert_equal 12, report["accounts"]["archive_count"]
    assert_equal 12, report["accounts"]["created"]
    assert_equal 8, report["categories"]["archive_count"]
    assert_equal 3, report["category_groups"]["created"]
    assert_equal 2, report["tags"]["created"]
    assert_equal 8, report["transactions"]["created"]
    assert_equal 7, report["balance_history"]["created"]
    assert_equal 3, report["holdings"]["created"]
    assert_equal 3, report["rules"]["created"]
    assert_equal 2, report["recurring_streams"]["created"]
    assert_equal 1, report["goals"]["created"]

    # budgets: future month rows skipped, group scope skipped
    assert_equal 1, report["budget_totals"]["created"]
    assert_equal 1, report["budget_totals"]["skipped"]["future_month"]
    assert_equal 2, report["budget_months"]["created"]
    assert_equal 1, report["budget_months"]["skipped"]["future_month"]
    assert_equal 1, report["budget_months"]["skipped"]["unsupported_scope:group"]

    # reference + derived collections never enter the ledger
    assert_equal 2, report["settings_documents"]["skipped"]["reference_only"]
    assert_equal 2, report["credit_scores"]["skipped"]["reference_only"]
    assert_equal 1, report["net_worth_daily"]["skipped"]["derived_or_not_applicable"]

    prefs = import.reference_documents["settings_documents"].find { |d| d["documentType"] == "householdPreferences" }
    assert_equal "America/Los_Angeles", prefs["data"]["timezone"]
  end

  test "account type and subtype mapping covers every Monarch pairing" do
    run_import

    assert_instance_of Depository, mapping_for("accounts", "acc-checking").record.accountable
    assert_equal "checking", mapping_for("accounts", "acc-checking").record.accountable.subtype
    assert_equal "savings", mapping_for("accounts", "acc-savings").record.accountable.subtype
    assert_instance_of CreditCard, mapping_for("accounts", "acc-credit").record.accountable
    assert_instance_of Crypto, mapping_for("accounts", "acc-crypto").record.accountable

    {
      "acc-brokerage" => "brokerage", "acc-401k" => "401k", "acc-ira" => "ira",
      "acc-roth" => "roth_ira", "acc-hsa" => "hsa", "acc-pension" => "pension"
    }.each do |mid, subtype|
      acc = mapping_for("accounts", mid).record
      assert_instance_of Investment, acc.accountable, "#{mid} should map to Investment"
      assert_equal subtype, acc.accountable.subtype, "#{mid} subtype mismatch"
    end
  end

  test "preserves account flags: hidden, deactivated, net-worth exclusion, institution" do
    run_import

    hidden = mapping_for("accounts", "acc-hidden").record
    assert_equal "disabled", hidden.status
    assert_equal Date.new(2026, 3, 4), hidden.disabled_at.to_date
    assert hidden.hide_from_list?
    assert_not hidden.include_in_net_worth?
    assert hidden.exclude_from_reports?
    assert hidden.hide_in_budget?

    # isHidden without deactivatedAt stays active: hidden from lists but
    # still counted in net worth and reports (Monarch semantics).
    list_hidden = mapping_for("accounts", "acc-hidden-only").record
    assert_equal "active", list_hidden.status
    assert list_hidden.hide_from_list?
    assert list_hidden.include_in_net_worth?
    assert_not list_hidden.exclude_from_reports?
    assert_not list_hidden.hide_in_budget?

    checking = mapping_for("accounts", "acc-checking").record
    assert_equal "active", checking.status
    assert_equal "First Test Bank", checking.institution_name
    assert_equal "cdn.example.com", checking.institution_domain

    # liability balances stored positive (single inversion, no double-flip)
    assert_equal 1450.75, mapping_for("accounts", "acc-credit").record.balance.to_f
  end

  test "transaction signs invert to Sure convention (positive = expense)" do
    run_import

    expense = mapping_for("transactions", "txn-1").record
    assert_equal 84.32, expense.amount.to_f
    income = mapping_for("transactions", "txn-2").record
    assert_equal(-2450.0, income.amount.to_f)
  end

  test "transaction flags: pending, needs_review, excluded, provider description" do
    run_import

    pending = mapping_for("transactions", "txn-4").record
    assert pending.transaction.extra.dig("monarch", "pending")
    assert pending.transaction.extra.dig("monarch", "needs_review")
    assert_equal "needs_review", pending.transaction.extra.dig("monarch", "review_status")
    assert pending.transaction.pending?
    # The provenance stays in extra, and the workflow flag lands on the row too
    assert pending.transaction.needs_review?

    reviewed = mapping_for("transactions", "txn-1").record
    assert_not reviewed.transaction.needs_review?

    hidden = mapping_for("transactions", "txn-7").record
    assert hidden.excluded?

    assert_equal "GROCERY MART #42 DEBIT PUR",
      mapping_for("transactions", "txn-1").record.transaction.extra.dig("monarch", "data_provider_description")
  end

  test "transfer-category transactions become funds_movement" do
    run_import

    assert_equal "funds_movement", mapping_for("transactions", "txn-5").record.transaction.kind
    assert_equal "standard", mapping_for("transactions", "txn-1").record.transaction.kind
  end

  test "transaction tags apply from transaction_tags and embedded tags" do
    run_import

    txn1 = mapping_for("transactions", "txn-1").record.transaction
    assert_equal %w[reimbursable vacation], txn1.tags.pluck(:name).sort

    txn2 = mapping_for("transactions", "txn-2").record.transaction
    assert_equal %w[reimbursable], txn2.tags.pluck(:name)
  end

  test "category groups carry Monarch type, order and color" do
    run_import

    expense_group = mapping_for("category_groups", "cg-expense").record
    assert_instance_of CategoryGroup, expense_group
    assert_equal "Everyday Expenses", expense_group.name
    assert_equal "expense", expense_group.classification
    assert_equal 1, expense_group.position
    assert_equal "#4da568", expense_group.color

    income_group = mapping_for("category_groups", "cg-income").record
    assert_equal "income", income_group.classification
    assert_equal 2, income_group.position
    assert_nil income_group.color # Monarch group colors can be null — preserved

    assert_equal "transfer", mapping_for("category_groups", "cg-transfer").record.classification
  end

  test "categories land in their group and inherit its classification" do
    run_import

    expense_group = mapping_for("category_groups", "cg-expense").record

    groceries = mapping_for("categories", "cat-groceries").record
    assert_equal expense_group, groceries.category_group
    assert_equal "expense", groceries.classification
    assert_nil groceries.parent # Monarch has no subcategories — imported flat

    # "Restaurants" collides with an existing subcategory — disambiguated by group name
    dining = mapping_for("categories", "cat-dining").record
    assert_equal "Everyday Expenses — Restaurants", dining.name
    assert_equal expense_group, dining.category_group

    assert_equal "income", mapping_for("categories", "cat-paychecks").record.classification
    assert_equal "income", mapping_for("categories", "cat-interest").record.classification
    assert_equal "transfer", mapping_for("categories", "cat-transfer").record.classification
    assert_equal "transfer", mapping_for("categories", "cat-ccpayment").record.classification
  end

  test "balance history becomes reconciliation valuations" do
    run_import

    entry = mapping_for("balance_history", "acc-checking:2026-09-15").record
    assert_instance_of Valuation, entry.entryable
    assert_equal "reconciliation", entry.entryable.kind
    assert_equal 4100.0, entry.amount.to_f

    # liability balances abs()'d once for Sure's positive-liability convention
    credit = mapping_for("balance_history", "acc-credit:2026-09-01").record
    assert_equal 1800.0, credit.amount.to_f
  end

  test "holdings create securities and preserve cost basis" do
    run_import

    holding = mapping_for("holdings", "hold-1").record
    assert_equal "AAPL", holding.security.ticker
    assert_equal "stock", holding.security.asset_sub_class
    assert_equal 10.0, holding.qty.to_f
    assert_equal 1800.0, holding.cost_basis.to_f
    assert_equal 2550.0, holding.amount.to_f

    crypto = mapping_for("holdings", "hold-2").record
    assert_equal "cryptocurrency", crypto.security.asset_sub_class
    assert crypto.cost_basis_source.nil? || crypto.cost_basis.nil?
  end

  test "rules map merchant/amount criteria to conditions and actions" do
    run_import

    rule = mapping_for("rules", "rule-1").record
    assert rule.active?
    name_cond = rule.conditions.find_by(condition_type: "transaction_name")
    assert_equal "like", name_cond.operator
    assert_equal "grocery", name_cond.value
    cat_action = rule.actions.find_by(action_type: "set_transaction_category")
    assert_equal mapping_for("categories", "cat-groceries").record_id.to_s, cat_action.value

    amount_rule = mapping_for("rules", "rule-2").record
    amt = amount_rule.conditions.find_by(condition_type: "transaction_amount")
    assert_equal ">", amt.operator
    assert_equal "20.0", amt.value
    assert_equal "expense", amount_rule.conditions.find_by(condition_type: "transaction_type").value

    tag_rule = mapping_for("rules", "rule-3").record
    tags_action = tag_rule.actions.find_by(action_type: "set_transaction_tags")
    assert_equal mapping_for("tags", "tag-reimb").record_id.to_s, tags_action.value
  end

  test "rules carry Monarch order into dense per-family positions" do
    run_import

    # Rule.reorder! writes dense 1..n positions (not Monarch's 0-based `order`)
    assert_equal 1, mapping_for("rules", "rule-1").record.position
    assert_equal 2, mapping_for("rules", "rule-2").record.position
    assert_equal 3, mapping_for("rules", "rule-3").record.position

    ordered = @family.rules.where(id: MonarchSourceMapping.where(family: @family, collection: "rules").select(:record_id)).ordered
    assert_equal %w[rule-1 rule-2 rule-3],
      ordered.map { |r| MonarchSourceMapping.find_by(family: @family, collection: "rules", record: r).monarch_id }
  end

  test "investment account cash position reconciles into the balance without double-counting" do
    import = run_import
    assert import.complete?

    # acc-brokerage: signedBalance 25000 with holdings AAPL 2550 + an explicit
    # cash position of 500. The cash position must not be added on top of the
    # total (double-counted into non-cash) nor dropped from the ledger.
    account = @family.accounts.find(mapping_for("accounts", "acc-brokerage").record_id)
    assert_equal 25_000, account.balance
    assert_equal 25_000, account.cash_balance

    cash_holding = account.holdings.joins(:security).find_by(securities: { kind: "cash" })
    assert_not_nil cash_holding, "the Monarch cash position should still import as a holding row"
    assert_equal 500, cash_holding.amount

    # On the cash holding's own date the position folds into cash, not on top.
    balance = account.balances.find_by(date: cash_holding.date)
    assert_equal 25_000, balance.balance
    assert_equal 25_000, balance.cash_balance
  end

  test "accounts without balance history keep their signed balance after materialization" do
    import = run_import
    assert import.complete?

    # The archive carries balance_history for only 4 accounts; the rest have
    # a signedBalance but no daily history. Each must get an anchor valuation
    # so the materializer doesn't zero them out.
    {
      "acc-401k"      => 80_000,
      "acc-ira"       => 15_000,
      "acc-roth"      => 9_000,
      "acc-hsa"       => 4_100,
      "acc-pension"   => 21_000,
      "acc-hidden"    => 200,   # liability abs()'d, per positive-liability convention
      "acc-hidden-only" => 500,
      "acc-crypto"    => 3_200
    }.each do |monarch_id, expected|
      account = @family.accounts.find(mapping_for("accounts", monarch_id).record_id)
      assert_equal expected, account.balance.to_f, "#{monarch_id} balance"
    end

    # Anchored accounts expose a materialized balance at the current date.
    account = @family.accounts.find(mapping_for("accounts", "acc-401k").record_id)
    assert_equal 80_000, account.balances.find_by(date: Date.current).balance

    # Re-importing must not create a second valuation for anchored accounts.
    assert_no_difference -> { Entry.where(entryable_type: "Valuation").count } do
      run_import
    end
  end

  test "anchor follows a changed signed balance on re-import" do
    run_import

    # A "newer archive": same fixture but acc-401k's balance changed.
    Dir.mktmpdir do |dir|
      FileUtils.cp_r("#{ARCHIVE}/.", dir)
      accounts_path = File.join(dir, "import", "accounts.json")
      accounts = JSON.parse(File.read(accounts_path))
      accounts.find { |a| a["id"] == "acc-401k" }.merge!(
        "signedBalance" => 85_000, "displayBalance" => 85_000, "currentBalance" => 85_000
      )
      File.write(accounts_path, JSON.pretty_generate(accounts))

      Monarch::Importer.new(family: @family, archive_path: dir, io: File.open(File::NULL, "w")).run
    end

    account = @family.accounts.find(mapping_for("accounts", "acc-401k").record_id)
    assert_equal 85_000, account.balance.to_f

    anchor = account.entries.find_by(source: "monarch", external_id: "anchor:acc-401k")
    assert_equal 85_000, anchor.amount.to_f
  end

  test "recurring streams map frequency and sign" do
    run_import

    rt = mapping_for("recurring_streams", "rs-1").record
    assert_equal 15.99, rt.amount.to_f # -15.99 expense -> positive in Sure
    assert_equal "monthly", rt.recurrence_rules.first.frequency
    assert_equal 10, rt.expected_day_of_month
    assert_equal "active", rt.status
    assert_equal "Streamflix", rt.merchant.name

    weekly = mapping_for("recurring_streams", "rs-2").record
    assert_equal(-100.0, weekly.amount.to_f)
    assert_equal "weekly", weekly.recurrence_rules.first.frequency
    assert_equal "income", weekly.bill_type
  end

  test "goal imports with whole-account allocation" do
    run_import

    goal = mapping_for("goals", "goal-1").record
    assert_equal 50000.0, goal.target_amount.to_f
    assert_equal "active", goal.state
    alloc = goal.goal_accounts.first
    assert_equal mapping_for("accounts", "acc-savings").record_id, alloc.account_id
    assert_nil alloc.allocated_amount # useEntireAccountBalance
  end

  test "report reconciles per-account transaction totals" do
    import = run_import

    totals = import.report["account_totals"]
    assert_equal 12, totals.size
    checking = totals["acc-checking"]
    # Monarch: -84.32 + 2450 - 52 - 1200 - 300 - 25 = 788.68
    assert_equal "788.68", checking["archive_total"]
    # Sure holds the inverse sign
    assert_equal(-788.68, checking["sure_total"].to_d)
  end

  test "idempotent: second run updates in place, no duplicates" do
    run_import
    counts = [ Entry, Account, Category, CategoryGroup, Tag, Merchant, Holding, Rule, RecurringTransaction, Budget, Goal, Valuation ].map(&:count)

    second = run_import
    assert second.complete?
    assert_equal counts, [ Entry, Account, Category, CategoryGroup, Tag, Merchant, Holding, Rule, RecurringTransaction, Budget, Goal, Valuation ].map(&:count)

    report = second.report["collections"]
    assert_equal 8, report["transactions"]["updated"]
    assert_equal 0, report["transactions"]["created"]
    assert_equal 12, report["accounts"]["updated"]
  end

  test "dry run writes nothing but still reports" do
    counts = [ Entry, Account, MonarchSourceMapping ].map(&:count)
    import = run_import(dry_run: true)

    assert_equal counts, [ Entry, Account, MonarchSourceMapping ].map(&:count)
    assert import.dry_run
    assert import.complete?
    assert_equal 8, import.report["collections"]["transactions"]["created"]
  end

  test "archive rows already merged into a provider entry are skipped, not resurrected" do
    # Simulate a prior dedup merge: the plaid winner absorbed monarch row
    # txn-1 and recorded its external_id in extra.manual_merge.
    winner = accounts(:depository).entries.create!(
      name: "SURVIVOR", date: Date.current, amount: 10.00, currency: "USD",
      source: "plaid", external_id: "plaid-1",
      entryable: Transaction.new(
        kind: "standard",
        extra: {
          "manual_merge" => [ {
            "merged_from_entry_id" => SecureRandom.uuid,
            "merged_from_external_id" => "txn-1",
            "merged_at" => Time.current.iso8601,
            "source" => "monarch",
            "via" => "dedup"
          } ]
        }
      )
    )

    import = run_import

    assert import.complete?
    report = import.report["collections"]
    assert_equal 7, report["transactions"]["created"]
    assert_equal 1, report["transactions"]["skipped"]["merged_duplicate"]
    assert_not Entry.exists?(source: "monarch", external_id: "txn-1")
  end

  test "revert removes everything the import created" do
    run_import
    Monarch::Reverter.new(family: @family, io: File.open(File::NULL, "w")).run

    assert_equal 0, MonarchSourceMapping.where(family: @family).count
    assert_equal 0, MonarchImport.where(family: @family).count
    assert_empty Entry.where(source: "monarch")
    assert_empty @family.accounts.where(name: "Everyday Checking")
    assert_empty @family.categories.where(name: "Groceries")
    assert_empty @family.category_groups.where(name: "Everyday Expenses")
  end
end
