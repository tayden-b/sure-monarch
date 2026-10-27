require "test_helper"

# The imported Monarch archive ends in a single as-of snapshot (valuation +
# offline holdings), while provider holdings/prices only begin part-way to
# the first provider anchor. Dates in between can't be repriced, so the
# imported total carries forward with entry flows instead of collapsing to
# the sparse holdings coverage.
class Balance::GapCarryForwardTest < ActiveSupport::TestCase
  include LedgerTestingHelper

  test "imported total carries through the gap until provider holdings coverage" do
    as_of = 28.days.ago.to_date
    anchor_date = Date.current

    account = create_linked_investment_account(
      provider: plaid_accounts(:one),
      as_of: as_of,
      imported_total: 165_102,
      imported_holdings: [
        { ticker: "FNDA", qty: 600, price: 100, amount: 60_000 },
        { ticker: "FNDB", qty: 525, price: 200, amount: 105_102 }
      ],
      anchor_total: 172_491,
      anchor_date: anchor_date,
      provider_holdings: (anchor_date - 3).upto(anchor_date).map do |date|
        { ticker: "VTI", date: date, qty: 300, price: 574.97, amount: 172_491 }
      end
    )

    Balance::Materializer.new(account, strategy: :reverse).materialize_balances
    first_pass = balance_map(account)

    # Re-materializing (a provider re-sync) must reproduce the same series.
    Balance::Materializer.new(account, strategy: :reverse).materialize_balances
    assert_equal first_pass.transform_values(&:end_balance), balance_map(account).transform_values(&:end_balance)

    as_of.upto(anchor_date - 4).each do |date|
      assert_equal 165_102, first_pass[date].end_balance, "expected carried imported total on #{date}"
    end

    (anchor_date - 3).upto(anchor_date - 1).each do |date|
      assert_equal 172_491, first_pass[date].end_balance, "expected provider-holdings value on #{date}"
    end

    assert_equal 172_491, first_pass[anchor_date].end_balance
  end

  test "imported total carries flat when provider has no holdings before the anchor" do
    as_of = 28.days.ago.to_date
    anchor_date = Date.current

    # Samsung 401k case: provider coverage only exists on the anchor date
    # itself, so every day after the snapshot carries the imported total.
    account = create_linked_investment_account(
      provider: plaid_accounts(:one),
      as_of: as_of,
      imported_total: 31_912,
      imported_holdings: [
        { ticker: "FSKAX", qty: 150, price: 212.75, amount: 31_912 }
      ],
      anchor_total: 31_294,
      anchor_date: anchor_date,
      provider_holdings: [
        { ticker: "FSKAX", date: anchor_date, qty: 155, price: 201.90, amount: 31_294 }
      ]
    )

    Balance::Materializer.new(account, strategy: :reverse).materialize_balances
    balances = balance_map(account)

    as_of.upto(anchor_date - 1).each do |date|
      assert_equal 31_912, balances[date].end_balance, "expected carried imported total on #{date}"
    end

    assert_equal 31_294, balances[anchor_date].end_balance
  end

  test "gap carry applies to crypto accounts" do
    as_of = 28.days.ago.to_date
    anchor_date = Date.current

    account = create_linked_investment_account(
      provider: kraken_accounts(:one),
      accountable_type: Crypto,
      as_of: as_of,
      imported_total: 18_940,
      imported_holdings: [
        { ticker: "SOL", qty: 80, price: 236.75, amount: 18_940 }
      ],
      anchor_total: 17_902,
      anchor_date: anchor_date,
      provider_holdings: [
        { ticker: "SOL", date: anchor_date, qty: 82, price: 218.32, amount: 17_902 }
      ]
    )

    Balance::Materializer.new(account, strategy: :reverse).materialize_balances
    balances = balance_map(account)

    as_of.upto(anchor_date - 1).each do |date|
      assert_equal 18_940, balances[date].end_balance, "expected carried imported total on #{date}"
    end

    assert_equal 17_902, balances[anchor_date].end_balance
  end

  test "cash-only accounts are unaffected" do
    anchor_date = Date.current
    txn_date = 3.days.ago.to_date

    account = create_account_with_ledger(
      account: { type: Depository, balance: 900, cash_balance: 900, currency: "USD" },
      entries: [
        { type: "current_anchor", date: anchor_date, balance: 900 },
        { type: "transaction", date: txn_date, amount: 200 }
      ]
    )

    account.entries.create!(
      name: "Imported balance",
      date: 7.days.ago.to_date,
      amount: 1_000,
      currency: account.currency,
      source: "monarch",
      entryable: Valuation.new(kind: "reconciliation")
    )

    imported_date = 7.days.ago.to_date
    Balance::Materializer.new(account, strategy: :reverse).materialize_balances
    balances = balance_map(account)

    # Cash accounts reverse-derive from the provider anchor: the spend
    # shows between the 1000-imported waypoint and the 900-anchor, and
    # nothing carries the imported valuation across the gap.
    assert_equal 1_000, balances[imported_date].end_balance
    assert_equal 1_100, balances[imported_date + 1].end_balance
    assert_equal 1_100, balances[txn_date].start_balance
    assert_equal 900, balances[txn_date].end_balance
  end

  private

    def create_linked_investment_account(provider:, as_of:, imported_total:, imported_holdings:, anchor_total:, anchor_date:, provider_holdings:, accountable_type: Investment)
      account = create_account_with_ledger(
        account: { type: accountable_type, balance: anchor_total, cash_balance: 0, currency: "USD" },
        entries: [
          { type: "opening_anchor", date: as_of - 30, balance: imported_total },
          { type: "current_anchor", date: anchor_date, balance: anchor_total }
        ],
        holdings: imported_holdings.map do |h|
          { ticker: h[:ticker], date: as_of, qty: h[:qty], price: h[:price], amount: h[:amount] }
        end
      )

      account.entries.create!(
        name: "Imported balance",
        date: as_of,
        amount: imported_total,
        currency: account.currency,
        source: "monarch",
        entryable: Valuation.new(kind: "reconciliation")
      )

      account_provider = account.account_providers.create!(provider: provider)

      provider_holdings.each do |h|
        security = Security.find_or_create_by!(ticker: h[:ticker]) { |s| s.name = h[:ticker] }
        Holding.create!(
          account: account,
          security: security,
          account_provider_id: account_provider.id,
          date: h[:date],
          qty: h[:qty],
          price: h[:price],
          amount: h[:amount],
          currency: account.currency
        )
      end

      account
    end

    def balance_map(account)
      account.balances.where(currency: account.currency).index_by(&:date)
    end
end
