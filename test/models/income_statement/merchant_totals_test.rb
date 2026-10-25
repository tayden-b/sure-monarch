require "test_helper"

class IncomeStatement::MerchantTotalsTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    @family = families(:empty)
    @checking = @family.accounts.create! name: "Checking", currency: @family.currency, balance: 5000, accountable: Depository.new
    @period = Period.custom(start_date: 9.days.ago.to_date, end_date: Date.current)
    @amazon = @family.merchants.create! name: "Amazon"
    @safeway = @family.merchants.create! name: "Safeway"
  end

  test "groups spend by merchant with transaction counts" do
    create_transaction(account: @checking, amount: 100, merchant: @amazon, date: 2.days.ago.to_date)
    create_transaction(account: @checking, amount: 50, merchant: @amazon, date: Date.current)
    create_transaction(account: @checking, amount: 25, merchant: @safeway)

    rows = merchant_totals.index_by(&:merchant_name)

    assert_equal 150, rows["Amazon"].total
    assert_equal 2, rows["Amazon"].transactions_count
    assert_equal 25, rows["Safeway"].total
    assert_equal 1, rows["Safeway"].transactions_count
  end

  test "ranks merchants by spend, top first" do
    create_transaction(account: @checking, amount: 25, merchant: @safeway)
    create_transaction(account: @checking, amount: 100, merchant: @amazon)

    assert_equal %w[Amazon Safeway], merchant_totals.map(&:merchant_name)
  end

  test "merchantless spend lands in a single no-merchant bucket" do
    create_transaction(account: @checking, amount: 100, merchant: nil)
    create_transaction(account: @checking, amount: 40, merchant: nil)
    create_transaction(account: @checking, amount: 25, merchant: @amazon)

    rows = merchant_totals.index_by(&:merchant_name)

    assert_equal 25, rows["Amazon"].total
    assert_equal 140, rows[nil].total
    assert_equal 2, rows[nil].transactions_count
  end

  test "collapses same-named merchants so the feed link reproduces the total" do
    provider_amazon = ProviderMerchant.create! name: "Amazon", source: "plaid"
    create_transaction(account: @checking, amount: 100, merchant: @amazon)
    create_transaction(account: @checking, amount: 30, merchant: provider_amazon)

    rows = merchant_totals

    assert_equal 1, rows.size
    assert_equal "Amazon", rows.first.merchant_name
    assert_equal 130, rows.first.total
    assert_equal 2, rows.first.transactions_count
  end

  test "excludes income, budget-excluded kinds, and pending transactions" do
    create_transaction(account: @checking, amount: -500, merchant: @amazon) # income direction
    create_transaction(account: @checking, amount: 40, merchant: @amazon, kind: "funds_movement")
    create_transaction(account: @checking, amount: 30, merchant: @amazon, kind: "cc_payment")
    pending_entry = create_transaction(account: @checking, amount: 20, merchant: @amazon)
    pending_entry.entryable.update!(extra: { "simplefin" => { "pending" => true } })
    create_transaction(account: @checking, amount: 10, merchant: @amazon)

    rows = merchant_totals

    assert_equal 1, rows.size
    assert_equal 10, rows.first.total
    assert_equal 1, rows.first.transactions_count
  end

  test "excludes entries marked as excluded" do
    create_transaction(account: @checking, amount: 100, merchant: @amazon, excluded: true)
    create_transaction(account: @checking, amount: 10, merchant: @amazon)

    rows = merchant_totals

    assert_equal 10, rows.first.total
    assert_equal 1, rows.first.transactions_count
  end

  test "excludes transactions in accounts flagged out of the statement's purpose" do
    hidden = @family.accounts.create! name: "Hidden", currency: @family.currency, balance: 0, accountable: Depository.new, exclude_from_reports: true
    create_transaction(account: hidden, amount: 100, merchant: @amazon)
    create_transaction(account: @checking, amount: 10, merchant: @amazon)

    assert_equal 10, merchant_totals.first.total
  end

  test "scopes to included account ids when given" do
    other = @family.accounts.create! name: "Other", currency: @family.currency, balance: 0, accountable: Depository.new
    create_transaction(account: @checking, amount: 10, merchant: @amazon)
    create_transaction(account: other, amount: 60, merchant: @safeway)

    rows = merchant_totals(included_account_ids: [ @checking.id ])

    assert_equal 1, rows.size
    assert_equal "Amazon", rows.first.merchant_name
  end

  test "returns no rows when the account scope is empty" do
    create_transaction(account: @checking, amount: 10, merchant: @amazon)

    assert_equal [], merchant_totals(included_account_ids: [])
  end

  test "converts foreign currency amounts at the day's exchange rate" do
    eur_account = @family.accounts.create! name: "EUR Checking", currency: "EUR", balance: 1000, accountable: Depository.new
    ExchangeRate.create! from_currency: "EUR", to_currency: @family.currency, date: Date.current, rate: 2

    create_transaction(account: eur_account, amount: 100, currency: "EUR", merchant: @amazon, date: Date.current)

    assert_equal 200, merchant_totals.first.total
  end

  test "limit keeps only the top N merchants" do
    create_transaction(account: @checking, amount: 10, merchant: @amazon)
    create_transaction(account: @checking, amount: 60, merchant: @safeway)
    create_transaction(account: @checking, amount: 200)

    rows = merchant_totals(limit: 2)

    assert_equal 2, rows.size
    assert_equal 200, rows.first.total
    assert_nil rows.first.merchant_name
  end

  private
    def merchant_totals(limit: nil, included_account_ids: nil)
      IncomeStatement::MerchantTotals.new(
        @family,
        transactions_scope: @family.transactions.visible.excluding_pending.in_period(@period),
        date_range: @period.date_range,
        included_account_ids: included_account_ids,
        account_flag: "exclude_from_reports",
        limit: limit
      ).call
    end
end
