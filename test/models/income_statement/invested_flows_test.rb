require "test_helper"

class IncomeStatement::InvestedFlowsTest < ActiveSupport::TestCase
  include EntriesTestHelper

  setup do
    # families(:empty) has the column default: contributions count as
    # savings (investment_contributions_count_as_expenses = false).
    @family = families(:empty)
    @checking = @family.accounts.create!(name: "Checking", currency: "USD", balance: 0, accountable: Depository.new)
    @investment = @family.accounts.create!(name: "Brokerage", currency: "USD", balance: 0, accountable: Investment.new)
    @period = Period.last_30_days
    @statement = IncomeStatement.new(@family)
  end

  test "contributions are excluded from expense totals and reported as invested" do
    create_transaction(account: @checking, amount: 1000, kind: "investment_contribution")
    create_transaction(account: @checking, amount: 500)

    totals = @statement.totals_for(@period)
    invested = @statement.invested_totals(period: @period)

    assert_equal Money.new(500, "USD"), totals.expense_money
    assert_equal 1000.to_d, invested.contributions
    assert_equal 0.to_d, invested.withdrawals
    assert_equal 1000.to_d, invested.net
    assert_equal "USD", invested.currency
  end

  test "provider-booked contribution inflows count regardless of sign" do
    # Payroll-style contribution imported by a provider lands in the
    # investment account as an inflow (negative amount), same population
    # upstream ABS's into expenses.
    create_transaction(account: @investment, amount: -500, kind: "investment_contribution")

    invested = @statement.invested_totals(period: @period)

    assert_equal 500.to_d, invested.contributions
    assert_equal 500.to_d, invested.net
  end

  test "withdrawal-labeled rows reduce invested" do
    create_transaction(account: @checking, amount: 1000, kind: "investment_contribution")
    create_transaction(account: @investment, amount: 200)
      .entryable.update!(investment_activity_label: "Withdrawal")

    invested = @statement.invested_totals(period: @period)

    assert_equal 1000.to_d, invested.contributions
    assert_equal 200.to_d, invested.withdrawals
    assert_equal 800.to_d, invested.net
  end

  test "transfers out of investment accounts reduce invested" do
    create_transaction(account: @checking, amount: 1000, kind: "investment_contribution")
    create_transfer(from_account: @investment, to_account: @checking, amount: 300)

    invested = @statement.invested_totals(period: @period)

    assert_equal 1000.to_d, invested.contributions
    assert_equal 300.to_d, invested.withdrawals
    assert_equal 700.to_d, invested.net
  end

  test "transfers between investment accounts are not withdrawals" do
    ira = @family.accounts.create!(name: "IRA", currency: "USD", balance: 0, accountable: Investment.new)
    create_transaction(account: @checking, amount: 1000, kind: "investment_contribution")
    create_transfer(from_account: @investment, to_account: ira, amount: 300)

    invested = @statement.invested_totals(period: @period)

    assert_equal 0.to_d, invested.withdrawals
    assert_equal 1000.to_d, invested.net
  end

  test "upstream mode keeps contributions in expenses but still reports invested" do
    @family.update!(investment_contributions_count_as_expenses: true)
    create_transaction(account: @checking, amount: 1000, kind: "investment_contribution")
    create_transaction(account: @checking, amount: 500)

    totals = @statement.totals_for(@period)
    invested = @statement.invested_totals(period: @period)

    assert_equal Money.new(1500, "USD"), totals.expense_money
    assert_equal 1000.to_d, invested.net
    assert_not @statement.investments_as_savings?
  end

  test "excluded and non-reportable rows stay out of invested" do
    create_transaction(account: @checking, amount: 1000, kind: "investment_contribution", excluded: true)
    hidden = @family.accounts.create!(name: "Hidden", currency: "USD", balance: 0, accountable: Depository.new, exclude_from_reports: true)
    create_transaction(account: hidden, amount: 700, kind: "investment_contribution")

    invested = @statement.invested_totals(period: @period)

    assert_equal 0.to_d, invested.net
  end
end
